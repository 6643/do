const std = @import("std");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const p3_async_manifest = @import("p3_async_manifest.zig");
const sema_tokens = @import("sema_tokens.zig");

const compact_token_range_equals = sema_tokens.compact_token_range_equals;
const find_matching = sema_tokens.find_matching;
const string_token_body = sema_tokens.string_token_body;
const tok_eq = sema_tokens.tok_eq;

const read_directory_locator = "wasi:filesystem/types@0.3.0-rc-2025-09-16";
const read_directory_member = "descriptor.read-directory";
const handles_type = "Tuple<Stream<DirectoryEntry>,Future<Result<nil,DirectoryError>>>";
const completion_type = "Future<Result<nil,DirectoryError>>";
const item_future_type = "Future<Result<DirectoryEntry,nil>>";
const item_result_type = "Result<DirectoryEntry,nil>";
pub const max_read_directory_reads: usize = 3;

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
    const plan = (try ReadDirectoryPlan.analyze(tokens, registry)) orelse return error.UnsupportedP3WasiReadDirectoryComponent;
    return emit_read_directory_wat(allocator, plan);
}

pub const ReadDirectoryPlan = struct {
    export_name: []const u8,
    descriptor: p3_async_manifest.Descriptor,
    directory_name: []const u8,
    handles_name: []const u8,
    reader_name: []const u8,
    completion_name: []const u8,
    pending_name: []const u8,
    entry_name: []const u8,
    completion_result_name: []const u8,
    read_count: usize,

    pub fn analyze(tokens: []const lexer.Token, registry: p3_async_manifest.Registry) !?ReadDirectoryPlan {
        const host = find_read_directory_host(tokens, registry) orelse return null;
        const function = find_read_directory_function(tokens) orelse return error.UnsupportedP3WasiReadDirectoryComponent;
        var pos = function.body_start;

        const handles = parse_handle_acquisition(tokens, pos, function.body_end, host.name, function.directory_name) orelse
            return error.UnsupportedP3WasiReadDirectoryComponent;
        pos = handles.next_idx;
        const reader = parse_reader_binding(tokens, pos, function.body_end, handles.handles_name) orelse
            return error.UnsupportedP3WasiReadDirectoryComponent;
        pos = reader.next_idx;
        const completion = parse_completion_binding(tokens, pos, function.body_end, handles.handles_name) orelse
            return error.UnsupportedP3WasiReadDirectoryComponent;
        pos = completion.next_idx;
        var read_count: usize = 0;
        var first_pending_name: ?[]const u8 = null;
        var first_entry_name: ?[]const u8 = null;
        while (true) {
            const pending = parse_next_binding(tokens, pos, function.body_end, reader.reader_name) orelse break;
            if (read_count >= max_read_directory_reads) return error.UnsupportedP3WasiReadDirectoryComponent;
            pos = pending.next_idx;
            const entry = parse_item_await(tokens, pos, function.body_end, pending.pending_name) orelse
                return error.UnsupportedP3WasiReadDirectoryComponent;
            pos = entry.next_idx;
            pos = parse_discard(tokens, pos, function.body_end, entry.entry_name) orelse
                return error.UnsupportedP3WasiReadDirectoryComponent;
            if (first_pending_name == null) first_pending_name = pending.pending_name;
            if (first_entry_name == null) first_entry_name = entry.entry_name;
            read_count += 1;
        }
        if (read_count == 0) return error.UnsupportedP3WasiReadDirectoryComponent;
        const completion_result = parse_completion_await(tokens, pos, function.body_end, completion.completion_name) orelse
            return error.UnsupportedP3WasiReadDirectoryComponent;
        pos = completion_result.next_idx;
        pos = parse_discard(tokens, pos, function.body_end, completion_result.result_name) orelse
            return error.UnsupportedP3WasiReadDirectoryComponent;
        if (pos >= function.body_end or !tok_eq(tokens[pos], "return") or pos + 1 != function.body_end) {
            return error.UnsupportedP3WasiReadDirectoryComponent;
        }

        return .{
            .export_name = function.name,
            .descriptor = host.descriptor,
            .directory_name = function.directory_name,
            .handles_name = handles.handles_name,
            .reader_name = reader.reader_name,
            .completion_name = completion.completion_name,
            .pending_name = first_pending_name.?,
            .entry_name = first_entry_name.?,
            .completion_result_name = completion_result.result_name,
            .read_count = read_count,
        };
    }
};

const ReadDirectoryHost = struct {
    name: []const u8,
    descriptor: p3_async_manifest.Descriptor,
};

const ReadDirectoryFunction = struct {
    name: []const u8,
    directory_name: []const u8,
    body_start: usize,
    body_end: usize,
};

const HandleBinding = struct {
    handles_name: []const u8,
    next_idx: usize,
};

const ReaderBinding = struct {
    reader_name: []const u8,
    next_idx: usize,
};

const CompletionBinding = struct {
    completion_name: []const u8,
    next_idx: usize,
};

const PendingBinding = struct {
    pending_name: []const u8,
    next_idx: usize,
};

const EntryBinding = struct {
    entry_name: []const u8,
    next_idx: usize,
};

const CompletionResultBinding = struct {
    result_name: []const u8,
    next_idx: usize,
};

fn find_read_directory_host(tokens: []const lexer.Token, registry: p3_async_manifest.Registry) ?ReadDirectoryHost {
    var idx: usize = 0;
    while (idx + 31 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "=") or !tok_eq(tokens[idx + 2], "@") or
            (!tok_eq(tokens[idx + 3], "host") and !tok_eq(tokens[idx + 3], "host_func")) or !tok_eq(tokens[idx + 4], "(") or
            tokens[idx + 5].kind != .string or !tok_eq(tokens[idx + 6], ",") or tokens[idx + 7].kind != .string or
            !tok_eq(tokens[idx + 8], ",") or !tok_eq(tokens[idx + 9], "(") or !tok_eq(tokens[idx + 10], "Dir") or
            !tok_eq(tokens[idx + 11], ")") or !tok_eq(tokens[idx + 12], "-") or !tok_eq(tokens[idx + 13], ">") or
            !tok_eq(tokens[idx + 14], "Tuple") or !tok_eq(tokens[idx + 15], "<") or !tok_eq(tokens[idx + 16], "Stream") or
            !tok_eq(tokens[idx + 17], "<") or !tok_eq(tokens[idx + 18], "DirectoryEntry") or !tok_eq(tokens[idx + 19], ">") or
            !tok_eq(tokens[idx + 20], ",") or !tok_eq(tokens[idx + 21], "Future") or !tok_eq(tokens[idx + 22], "<") or
            !tok_eq(tokens[idx + 23], "Result") or !tok_eq(tokens[idx + 24], "<") or !tok_eq(tokens[idx + 25], "nil") or
            !tok_eq(tokens[idx + 26], ",") or !tok_eq(tokens[idx + 27], "DirectoryError") or !tok_eq(tokens[idx + 28], ">") or
            !tok_eq(tokens[idx + 29], ">") or !tok_eq(tokens[idx + 30], ">") or !tok_eq(tokens[idx + 31], ")")) continue;
        const locator = string_token_body(tokens[idx + 5].lexeme) orelse continue;
        const member = string_token_body(tokens[idx + 7].lexeme) orelse continue;
        if (!std.mem.eql(u8, locator, read_directory_locator) or !std.mem.eql(u8, member, read_directory_member)) continue;
        const descriptor = registry.find(locator, member) orelse continue;
        switch (p3_async_manifest.lowering_shape(descriptor) orelse continue) {
            .record_stream_reader => return .{ .name = tokens[idx].lexeme, .descriptor = descriptor },
            else => continue,
        }
    }
    return null;
}

fn find_read_directory_function(tokens: []const lexer.Token) ?ReadDirectoryFunction {
    var found: ?ReadDirectoryFunction = null;
    var idx: usize = 0;
    while (idx + 8 < tokens.len) : (idx += 1) {
        if (!tok_eq(tokens[idx], "async") or tokens[idx + 1].kind != .ident or !tok_eq(tokens[idx + 2], "(") or
            tokens[idx + 3].kind != .ident or !tok_eq(tokens[idx + 4], "Dir") or !tok_eq(tokens[idx + 5], ")") or
            !tok_eq(tokens[idx + 6], "-") or !tok_eq(tokens[idx + 7], ">") or !tok_eq(tokens[idx + 8], "nil")) continue;
        var body_open = idx + 9;
        while (body_open < tokens.len and !tok_eq(tokens[body_open], "{")) : (body_open += 1) {}
        if (body_open >= tokens.len) return null;
        const body_end = find_matching(tokens, body_open, "{", "}") catch return null;
        if (found != null) return null;
        found = .{
            .name = tokens[idx + 1].lexeme,
            .directory_name = tokens[idx + 3].lexeme,
            .body_start = body_open + 1,
            .body_end = body_end,
        };
        idx = body_end;
    }
    return found;
}

fn parse_handle_acquisition(tokens: []const lexer.Token, idx: usize, end_idx: usize, host_name: []const u8, directory_name: []const u8) ?HandleBinding {
    if (idx + 5 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "Tuple") or !tok_eq(tokens[idx + 2], "<")) return null;
    const tuple_close = find_matching(tokens, idx + 2, "<", ">") catch return null;
    if (!compact_token_range_equals(tokens, idx + 1, tuple_close + 1, handles_type) or
        !tok_eq(tokens[tuple_close + 1], "=") or tokens[tuple_close + 2].kind != .ident or
        !std.mem.eql(u8, tokens[tuple_close + 2].lexeme, host_name) or !tok_eq(tokens[tuple_close + 3], "(") or
        tokens[tuple_close + 4].kind != .ident or !std.mem.eql(u8, tokens[tuple_close + 4].lexeme, directory_name) or
        !tok_eq(tokens[tuple_close + 5], ")")) return null;
    return .{ .handles_name = tokens[idx].lexeme, .next_idx = tuple_close + 6 };
}

fn parse_reader_binding(tokens: []const lexer.Token, idx: usize, end_idx: usize, handles_name: []const u8) ?ReaderBinding {
    if (idx + 8 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "Stream") or !tok_eq(tokens[idx + 2], "<")) return null;
    const type_close = find_matching(tokens, idx + 2, "<", ">") catch return null;
    if (!compact_token_range_equals(tokens, idx + 1, type_close + 1, "Stream<DirectoryEntry>") or
        !tok_eq(tokens[type_close + 1], "=") or !tok_eq(tokens[type_close + 2], "@") or !tok_eq(tokens[type_close + 3], "get") or
        !tok_eq(tokens[type_close + 4], "(") or tokens[type_close + 5].kind != .ident or !std.mem.eql(u8, tokens[type_close + 5].lexeme, handles_name) or
        !tok_eq(tokens[type_close + 6], ",") or !tok_eq(tokens[type_close + 7], "0") or !tok_eq(tokens[type_close + 8], ")")) return null;
    return .{ .reader_name = tokens[idx].lexeme, .next_idx = type_close + 9 };
}

fn parse_completion_binding(tokens: []const lexer.Token, idx: usize, end_idx: usize, handles_name: []const u8) ?CompletionBinding {
    if (idx + 8 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "Future") or !tok_eq(tokens[idx + 2], "<")) return null;
    const type_close = find_matching(tokens, idx + 2, "<", ">") catch return null;
    if (!compact_token_range_equals(tokens, idx + 1, type_close + 1, completion_type) or
        !tok_eq(tokens[type_close + 1], "=") or !tok_eq(tokens[type_close + 2], "@") or !tok_eq(tokens[type_close + 3], "get") or
        !tok_eq(tokens[type_close + 4], "(") or tokens[type_close + 5].kind != .ident or !std.mem.eql(u8, tokens[type_close + 5].lexeme, handles_name) or
        !tok_eq(tokens[type_close + 6], ",") or !tok_eq(tokens[type_close + 7], "1") or !tok_eq(tokens[type_close + 8], ")")) return null;
    return .{ .completion_name = tokens[idx].lexeme, .next_idx = type_close + 9 };
}

fn parse_next_binding(tokens: []const lexer.Token, idx: usize, end_idx: usize, reader_name: []const u8) ?PendingBinding {
    if (idx + 6 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "Future") or !tok_eq(tokens[idx + 2], "<")) return null;
    const type_close = find_matching(tokens, idx + 2, "<", ">") catch return null;
    if (!compact_token_range_equals(tokens, idx + 1, type_close + 1, item_future_type) or
        !tok_eq(tokens[type_close + 1], "=") or !tok_eq(tokens[type_close + 2], "@") or !tok_eq(tokens[type_close + 3], "next") or
        !tok_eq(tokens[type_close + 4], "(") or tokens[type_close + 5].kind != .ident or !std.mem.eql(u8, tokens[type_close + 5].lexeme, reader_name) or
        !tok_eq(tokens[type_close + 6], ")")) return null;
    return .{ .pending_name = tokens[idx].lexeme, .next_idx = type_close + 7 };
}

fn parse_item_await(tokens: []const lexer.Token, idx: usize, end_idx: usize, pending_name: []const u8) ?EntryBinding {
    if (idx + 5 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "Result") or !tok_eq(tokens[idx + 2], "<")) return null;
    const type_close = find_matching(tokens, idx + 2, "<", ">") catch return null;
    if (!compact_token_range_equals(tokens, idx + 1, type_close + 1, item_result_type) or
        !tok_eq(tokens[type_close + 1], "=") or !tok_eq(tokens[type_close + 2], "await") or !tok_eq(tokens[type_close + 3], "(") or
        tokens[type_close + 4].kind != .ident or !std.mem.eql(u8, tokens[type_close + 4].lexeme, pending_name) or !tok_eq(tokens[type_close + 5], ")")) return null;
    return .{ .entry_name = tokens[idx].lexeme, .next_idx = type_close + 6 };
}

fn parse_completion_await(tokens: []const lexer.Token, idx: usize, end_idx: usize, completion_name: []const u8) ?CompletionResultBinding {
    if (idx + 5 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "Result") or !tok_eq(tokens[idx + 2], "<")) return null;
    const type_close = find_matching(tokens, idx + 2, "<", ">") catch return null;
    if (!compact_token_range_equals(tokens, idx + 1, type_close + 1, "Result<nil,DirectoryError>") or
        !tok_eq(tokens[type_close + 1], "=") or !tok_eq(tokens[type_close + 2], "await") or !tok_eq(tokens[type_close + 3], "(") or
        tokens[type_close + 4].kind != .ident or !std.mem.eql(u8, tokens[type_close + 4].lexeme, completion_name) or !tok_eq(tokens[type_close + 5], ")")) return null;
    return .{ .result_name = tokens[idx].lexeme, .next_idx = type_close + 6 };
}

fn parse_discard(tokens: []const lexer.Token, idx: usize, end_idx: usize, name: []const u8) ?usize {
    if (idx + 2 >= end_idx or !tok_eq(tokens[idx], "_") or !tok_eq(tokens[idx + 1], "=") or tokens[idx + 2].kind != .ident or
        !std.mem.eql(u8, tokens[idx + 2].lexeme, name)) return null;
    return idx + 3;
}

const read_directory_core_wat =
    \\(module
    \\  (type $read-directory (func (param i32 i32) (result i32)))
    \\  (type $stream-new (func (result i64)))
    \\  (type $stream-cancel (func (param i32) (result i32)))
    \\  (type $stream-drop (func (param i32)))
    \\  (type $stream-read (func (param i32 i32 i32) (result i32)))
    \\  (type $future-new (func (result i64)))
    \\  (type $future-cancel (func (param i32) (result i32)))
    \\  (type $future-drop (func (param i32)))
    \\  (type $future-read (func (param i32 i32) (result i32)))
    \\  (type $resource-drop (func (param i32)))
    \\  (type $waitable-new (func (result i32)))
    \\  (type $waitable-join (func (param i32 i32)))
    \\  (type $waitable-drop (func (param i32)))
    \\  (type $context-get (func (result i32)))
    \\  (type $context-set (func (param i32)))
    \\  (type $async-run (func (param i32) (result i32)))
    \\  (type $async-callback (func (param i32 i32 i32) (result i32)))
    \\  (type $task-return (func))
    \\  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))
    \\  (type $initialize (func))
    \\  (import "[method-module]" "[method-name]" (func $read-directory (type $read-directory)))
    \\  (import "[method-module]" "[stream-new-name]" (func $stream-new (type $stream-new)))
    \\  (import "[method-module]" "[stream-cancel-read-name]" (func $stream-cancel-read (type $stream-cancel)))
    \\  (import "[method-module]" "[stream-cancel-write-name]" (func $stream-cancel-write (type $stream-cancel)))
    \\  (import "[method-module]" "[stream-drop-readable-name]" (func $stream-drop-readable (type $stream-drop)))
    \\  (import "[method-module]" "[stream-drop-writable-name]" (func $stream-drop-writable (type $stream-drop)))
    \\  (import "[method-module]" "[stream-read-name]" (func $stream-read (type $stream-read)))
    \\  (import "[method-module]" "[stream-write-name]" (func $stream-write (type $stream-read)))
    \\  (import "[method-module]" "[future-new-name]" (func $future-new (type $future-new)))
    \\  (import "[method-module]" "[future-cancel-read-name]" (func $future-cancel-read (type $future-cancel)))
    \\  (import "[method-module]" "[future-cancel-write-name]" (func $future-cancel-write (type $future-cancel)))
    \\  (import "[method-module]" "[future-drop-readable-name]" (func $future-drop-readable (type $future-drop)))
    \\  (import "[method-module]" "[future-drop-writable-name]" (func $future-drop-writable (type $future-drop)))
    \\  (import "[method-module]" "[future-read-name]" (func $future-read (type $future-read)))
    \\  (import "[method-module]" "[future-write-name]" (func $future-write (type $future-read)))
    \\  (import "[method-module]" "[resource-drop-name]" (func $descriptor-drop (type $resource-drop)))
    \\  (import "$root" "[waitable-set-new]" (func $waitable-set-new (type $waitable-new)))
    \\  (import "$root" "[waitable-join]" (func $waitable-join (type $waitable-join)))
    \\  (import "$root" "[waitable-set-drop]" (func $waitable-set-drop (type $waitable-drop)))
    \\  (import "$root" "[context-get-0]" (func $context-get-0 (type $context-get)))
    \\  (import "$root" "[context-set-0]" (func $context-set-0 (type $context-set)))
    \\  (import "[export][task-return-locator]" "[task-return-name]" (func $task-return (type $task-return)))
    \\  (memory (export "memory") 2)
    \\  ;; directory-entry result area: descriptor-type, string.ptr, string.len
    \\  ;; record-layout directory-entry: type@[record-type-offset] name-ptr@[record-name-ptr-offset] name-len@[record-name-len-offset]
    \\  ;; bounded remaining reads are stored at frame+16
    \\  (global $frame-next (mut i32) (i32.const 1024))
    \\  (global $heap-next (mut i32) (i32.const 65536))
    \\  (func $frame-alloc (result i32)
    \\    global.get $frame-next
    \\    global.get $frame-next
    \\    i32.const 96
    \\    i32.add
    \\    global.set $frame-next
    \\  )
    \\  (func $frame-free (param $frame i32))
    \\  (func $wait-on-directory (param $frame i32) (result i32)
    \\    local.get $frame
    \\    i32.const 20
    \\    i32.add
    \\    i32.load
    \\    i32.const 4
    \\    i32.shr_u
    \\    local.get $frame
    \\    i32.load
    \\    call $waitable-join
    \\    local.get $frame
    \\    i32.load
    \\    i32.const 4
    \\    i32.shl
    \\    i32.const 2
    \\    i32.or
    \\  )
    \\  (func $wait-on-stream (param $frame i32) (result i32)
    \\    local.get $frame
    \\    i32.const 8
    \\    i32.add
    \\    i32.load
    \\    local.get $frame
    \\    i32.load
    \\    call $waitable-join
    \\    local.get $frame
    \\    i32.load
    \\    i32.const 4
    \\    i32.shl
    \\    i32.const 2
    \\    i32.or
    \\  )
    \\  (func $wait-on-completion (param $frame i32) (result i32)
    \\    local.get $frame
    \\    i32.const 12
    \\    i32.add
    \\    i32.load
    \\    local.get $frame
    \\    i32.load
    \\    call $waitable-join
    \\    local.get $frame
    \\    i32.load
    \\    i32.const 4
    \\    i32.shl
    \\    i32.const 2
    \\    i32.or
    \\  )
    \\  (func $cleanup (param $frame i32) (result i32) (local $handle i32)
    \\    local.get $frame
    \\    i32.const 12
    \\    i32.add
    \\    i32.load
    \\    local.tee $handle
    \\    i32.eqz
    \\    if
    \\    else
    \\      local.get $handle
    \\      call $future-drop-readable
    \\      local.get $frame
    \\      i32.const 12
    \\      i32.add
    \\      i32.const 0
    \\      i32.store
    \\    end
    \\    local.get $frame
    \\    i32.const 8
    \\    i32.add
    \\    i32.load
    \\    local.tee $handle
    \\    i32.eqz
    \\    if
    \\    else
    \\      local.get $handle
    \\      call $stream-drop-readable
    \\      local.get $frame
    \\      i32.const 8
    \\      i32.add
    \\      i32.const 0
    \\      i32.store
    \\    end
    \\    local.get $frame
    \\    i32.const 4
    \\    i32.add
    \\    i32.load
    \\    local.tee $handle
    \\    i32.eqz
    \\    if
    \\    else
    \\      local.get $handle
    \\      call $descriptor-drop
    \\      local.get $frame
    \\      i32.const 4
    \\      i32.add
    \\      i32.const 0
    \\      i32.store
    \\    end
    \\    local.get $frame
    \\    i32.load
    \\    call $waitable-set-drop
    \\    i32.const 0
    \\    call $context-set-0
    \\    local.get $frame
    \\    call $frame-free
    \\    call $task-return
    \\    i32.const 0
    \\  )
    \\  (func $consume-entry (param $frame i32)
    \\    local.get $frame
    \\    i32.const 64
    \\    i32.add
    \\    i32.const [record-type-offset]
    \\    i32.add
    \\    i32.load
    \\    drop
    \\    local.get $frame
    \\    i32.const 64
    \\    i32.add
    \\    i32.const [record-name-ptr-offset]
    \\    i32.add
    \\    i32.load
    \\    drop
    \\    local.get $frame
    \\    i32.const 64
    \\    i32.add
    \\    i32.const [record-name-len-offset]
    \\    i32.add
    \\    i32.load
    \\    drop
    \\  )
    \\  (func $advance-stream (param $frame i32) (result i32) (local $remaining i32)
    \\    local.get $frame
    \\    i32.const 16
    \\    i32.add
    \\    i32.load
    \\    i32.const 1
    \\    i32.sub
    \\    local.set $remaining
    \\    local.get $frame
    \\    i32.const 16
    \\    i32.add
    \\    local.get $remaining
    \\    i32.store
    \\    local.get $remaining
    \\    i32.eqz
    \\    if (result i32)
    \\      local.get $frame
    \\      call $start-completion
    \\    else
    \\      local.get $frame
    \\      call $start-stream
    \\    end
    \\  )
    \\  (func $accept-completion (param $frame i32) (param $code i32) (result i32)
    \\    local.get $frame
    \\    call $cleanup
    \\  )
    \\  (func $start-completion (param $frame i32) (result i32) (local $code i32)
    \\    local.get $frame
    \\    i32.const 12
    \\    i32.add
    \\    i32.load
    \\    local.get $frame
    \\    i32.const 80
    \\    i32.add
    \\    call $future-read
    \\    local.tee $code
    \\    i32.const -1
    \\    i32.eq
    \\    if (result i32)
    \\      local.get $frame
    \\      call $wait-on-completion
    \\    else
    \\      local.get $frame
    \\      local.get $code
    \\      call $accept-completion
    \\    end
    \\  )
    \\  (func $accept-stream (param $frame i32) (param $code i32) (result i32)
    \\    local.get $code
    \\    i32.const 1
    \\    i32.eq
    \\    if (result i32)
    \\      local.get $frame
    \\      call $start-completion
    \\    else
    \\      local.get $code
    \\      i32.const 16
    \\      i32.eq
    \\      if (result i32)
    \\        local.get $frame
    \\        call $consume-entry
    \\        local.get $frame
    \\        call $advance-stream
    \\      else
    \\        local.get $code
    \\        i32.const 17
    \\        i32.eq
    \\        if (result i32)
    \\          local.get $frame
    \\          call $start-completion
    \\        else
    \\          unreachable
    \\        end
    \\      end
    \\    end
    \\  )
    \\  (func $start-stream (param $frame i32) (result i32) (local $code i32)
    \\    local.get $frame
    \\    i32.const 8
    \\    i32.add
    \\    i32.load
    \\    local.get $frame
    \\    i32.const 64
    \\    i32.add
    \\    i32.const 1
    \\    call $stream-read
    \\    local.tee $code
    \\    i32.const -1
    \\    i32.eq
    \\    if (result i32)
    \\      local.get $frame
    \\      call $wait-on-stream
    \\    else
    \\      local.get $frame
    \\      local.get $code
    \\      call $accept-stream
    \\    end
    \\  )
    \\  (func $accept-directory (param $frame i32) (param $code i32) (result i32)
    \\    local.get $frame
    \\    i32.const 8
    \\    i32.add
    \\    local.get $frame
    \\    i32.const 24
    \\    i32.add
    \\    i32.load
    \\    i32.store
    \\    local.get $frame
    \\    i32.const 12
    \\    i32.add
    \\    local.get $frame
    \\    i32.const 28
    \\    i32.add
    \\    i32.load
    \\    i32.store
    \\    local.get $frame
    \\    call $start-stream
    \\  )
    \\  (func $start-directory (param $frame i32) (result i32) (local $code i32)
    \\    local.get $frame
    \\    i32.const 4
    \\    i32.add
    \\    i32.load
    \\    local.get $frame
    \\    i32.const 24
    \\    i32.add
    \\    call $read-directory
    \\    local.set $code
    \\    local.get $frame
    \\    i32.const 20
    \\    i32.add
    \\    local.get $code
    \\    i32.store
    \\    local.get $code
    \\    i32.const 2
    \\    i32.eq
    \\    if (result i32)
    \\      local.get $frame
    \\      i32.const 2
    \\      call $accept-directory
    \\    else
    \\      local.get $frame
    \\      call $wait-on-directory
    \\    end
    \\  )
    \\  (func (export "[async-lift-name]") (type $async-run) (param $directory i32) (result i32) (local $frame i32)
    \\    call $frame-alloc
    \\    local.tee $frame
    \\    call $context-set-0
    \\    local.get $frame
    \\    call $waitable-set-new
    \\    i32.store
    \\    local.get $frame
    \\    i32.const 4
    \\    i32.add
    \\    local.get $directory
    \\    i32.store
    \\    local.get $frame
    \\    i32.const 24
    \\    i32.add
    \\    i32.const 256
    \\    i32.store
    \\    local.get $frame
    \\    i32.const 16
    \\    i32.add
    \\    i32.const [read-count]
    \\    i32.store
    \\    local.get $frame
    \\    call $start-directory
    \\  )
    \\  (func (export "[callback-async-lift-name]") (type $async-callback) (param $event i32) (param $index i32) (param $payload i32) (result i32) (local $frame i32)
    \\    call $context-get-0
    \\    local.set $frame
    \\    local.get $event
    \\    i32.const 1
    \\    i32.eq
    \\    if (result i32)
    \\      local.get $frame
    \\      local.get $payload
    \\      call $accept-directory
    \\    else
    \\      local.get $event
    \\      i32.const 2
    \\      i32.eq
    \\      if (result i32)
    \\        local.get $frame
    \\        local.get $payload
    \\        call $accept-stream
    \\      else
    \\        local.get $event
    \\        i32.const 4
    \\        i32.eq
    \\        if (result i32)
    \\          local.get $frame
    \\          local.get $payload
    \\          call $accept-completion
    \\        else
    \\          unreachable
    \\        end
    \\      end
    \\    end
    \\  )
    \\  (func (export "cabi_realloc") (type $cabi-realloc) (param $old i32) (param $old-size i32) (param $align i32) (param $size i32) (result i32)
    \\    (local $ptr i32)
    \\    local.get $old
    \\    i32.eqz
    \\    if (result i32)
    \\      global.get $heap-next
    \\      local.set $ptr
    \\      local.get $ptr
    \\      local.get $size
    \\      i32.add
    \\      global.set $heap-next
    \\      local.get $ptr
    \\    else
    \\      local.get $old
    \\    end
    \\  )
    \\  (func (export "_initialize") (type $initialize))
    \\)
;

const read_directory_component_wit =
    \\package wasi:filesystem@0.3.0-rc-2025-09-16;
    \\
    \\interface types {
    \\  enum descriptor-type { unknown, directory, regular-file }
    \\  record directory-entry {
    \\    %type: descriptor-type,
    \\    name: string,
    \\  }
    \\  enum error-code { access, io, no-entry }
    \\  resource descriptor {
    \\    read-directory: async func() -> tuple<stream<directory-entry>, future<result<_, error-code>>>;
    \\  }
    \\}
    \\
    \\interface probe {
    \\  use types.{descriptor};
    \\  [export-name]: async func(directory: own<descriptor>);
    \\}
    \\
    \\world read-directory-probe {
    \\  import types;
    \\  export probe;
    \\}
;

pub fn emit_component_wit(allocator: std.mem.Allocator, tokens: []const lexer.Token) anyerror![]u8 {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    const plan = (try ReadDirectoryPlan.analyze(tokens, registry)) orelse return error.UnsupportedP3WasiReadDirectoryComponent;
    return emit_read_directory_wit(allocator, plan);
}

fn emit_read_directory_wat(allocator: std.mem.Allocator, plan: ReadDirectoryPlan) ![]u8 {
    var wat = try allocator.dupe(u8, read_directory_core_wat);
    errdefer allocator.free(wat);
    const record_shape = switch (p3_async_manifest.lowering_shape(plan.descriptor) orelse return error.UnsupportedP3WasiReadDirectoryComponent) {
        .record_stream_reader => |shape| shape,
        else => return error.UnsupportedP3WasiReadDirectoryComponent,
    };
    const record_layout = record_shape.record_layout orelse return error.UnsupportedP3WasiReadDirectoryComponent;
    const record_type_offset = record_layout.field_offset("type") orelse return error.UnsupportedP3WasiReadDirectoryComponent;
    const record_name_ptr_offset = record_layout.field_offset("name-ptr") orelse return error.UnsupportedP3WasiReadDirectoryComponent;
    const record_name_len_offset = record_layout.field_offset("name-len") orelse return error.UnsupportedP3WasiReadDirectoryComponent;
    const export_name = try sanitized_export_name(allocator, plan.export_name);
    defer allocator.free(export_name);
    const read_count_text = try std.fmt.allocPrint(allocator, "{d}", .{plan.read_count});
    defer allocator.free(read_count_text);
    const record_type_offset_text = try std.fmt.allocPrint(allocator, "{d}", .{record_type_offset});
    defer allocator.free(record_type_offset_text);
    const record_name_ptr_offset_text = try std.fmt.allocPrint(allocator, "{d}", .{record_name_ptr_offset});
    defer allocator.free(record_name_ptr_offset_text);
    const record_name_len_offset_text = try std.fmt.allocPrint(allocator, "{d}", .{record_name_len_offset});
    defer allocator.free(record_name_len_offset_text);
    const task_return_name = try std.fmt.allocPrint(allocator, "[task-return]{s}", .{export_name});
    defer allocator.free(task_return_name);
    const async_lift_name = try std.fmt.allocPrint(allocator, "[async-lift]wasi:filesystem/probe@0.3.0-rc-2025-09-16#{s}", .{export_name});
    defer allocator.free(async_lift_name);
    const callback_async_lift_name = try std.fmt.allocPrint(allocator, "[callback][async-lift]wasi:filesystem/probe@0.3.0-rc-2025-09-16#{s}", .{export_name});
    defer allocator.free(callback_async_lift_name);
    const replacements = [_][2][]const u8{
        .{ "[method-module]", plan.descriptor.canonical.async_import_module },
        .{ "[method-name]", plan.descriptor.canonical.async_import_name },
        .{ "[stream-new-name]", plan.descriptor.canonical.stream.?.new.import_name },
        .{ "[stream-cancel-read-name]", plan.descriptor.canonical.stream.?.cancel_read.import_name },
        .{ "[stream-cancel-write-name]", plan.descriptor.canonical.stream.?.cancel_write.import_name },
        .{ "[stream-drop-readable-name]", plan.descriptor.canonical.stream.?.drop_readable.import_name },
        .{ "[stream-drop-writable-name]", plan.descriptor.canonical.stream.?.drop_writable.import_name },
        .{ "[stream-read-name]", plan.descriptor.canonical.stream.?.read.import_name },
        .{ "[stream-write-name]", plan.descriptor.canonical.stream.?.write.import_name },
        .{ "[future-new-name]", plan.descriptor.canonical.future.?.new.?.import_name },
        .{ "[future-cancel-read-name]", plan.descriptor.canonical.future.?.cancel_read.?.import_name },
        .{ "[future-cancel-write-name]", plan.descriptor.canonical.future.?.cancel_write.?.import_name },
        .{ "[future-drop-readable-name]", plan.descriptor.canonical.future.?.drop_readable.import_name },
        .{ "[future-drop-writable-name]", plan.descriptor.canonical.future.?.drop_writable.?.import_name },
        .{ "[future-read-name]", plan.descriptor.canonical.future.?.read.?.import_name },
        .{ "[future-write-name]", plan.descriptor.canonical.future.?.write.?.import_name },
        .{ "[resource-drop-name]", "[resource-drop]descriptor" },
        .{ "[task-return-locator]", "wasi:filesystem/probe@0.3.0-rc-2025-09-16" },
        .{ "[task-return-name]", task_return_name },
        .{ "[async-lift-name]", async_lift_name },
        .{ "[callback-async-lift-name]", callback_async_lift_name },
        .{ "[read-count]", read_count_text },
        .{ "[record-type-offset]", record_type_offset_text },
        .{ "[record-name-ptr-offset]", record_name_ptr_offset_text },
        .{ "[record-name-len-offset]", record_name_len_offset_text },
    };
    for (replacements) |replacement| {
        wat = try replace_and_free(allocator, wat, replacement[0], replacement[1]);
    }
    return wat;
}

fn emit_read_directory_wit(allocator: std.mem.Allocator, plan: ReadDirectoryPlan) ![]u8 {
    const export_name = try sanitized_export_name(allocator, plan.export_name);
    defer allocator.free(export_name);
    const wit = try allocator.dupe(u8, read_directory_component_wit);
    return replace_and_free(allocator, wit, "[export-name]", export_name);
}

fn sanitized_export_name(allocator: std.mem.Allocator, source_name: []const u8) ![]u8 {
    const export_name = try allocator.dupe(u8, source_name);
    for (export_name) |*ch| {
        if (ch.* == '_') ch.* = '-';
    }
    return export_name;
}

fn replace_and_free(allocator: std.mem.Allocator, input: []u8, needle: []const u8, replacement: []const u8) ![]u8 {
    const replaced = try replace_all(allocator, input, needle, replacement);
    allocator.free(input);
    return replaced;
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
    const removed = count * needle.len;
    const added = count * replacement.len;
    var output = try allocator.alloc(u8, if (added >= removed) input.len + added - removed else input.len - (removed - added));
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

test "read-directory plan accepts one entry read and independent completion await" {
    const source =
        \\read_directory = @host("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.read-directory", (Dir) -> Tuple<Stream<DirectoryEntry>, Future<Result<nil, DirectoryError>>>)
        \\async run(dir Dir) -> nil {
        \\    handles Tuple<Stream<DirectoryEntry>, Future<Result<nil, DirectoryError>>> = read_directory(dir)
        \\    reader Stream<DirectoryEntry> = @get(handles, 0)
        \\    completion Future<Result<nil, DirectoryError>> = @get(handles, 1)
        \\    pending Future<Result<DirectoryEntry, nil>> = @next(reader)
        \\    entry Result<DirectoryEntry, nil> = await(pending)
        \\    _ = entry
        \\    completed Result<nil, DirectoryError> = await(completion)
        \\    _ = completed
        \\    return
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const plan = try ReadDirectoryPlan.analyze(tokens, registry) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("run", plan.export_name);
    try std.testing.expectEqualStrings("dir", plan.directory_name);
    try std.testing.expectEqualStrings("reader", plan.reader_name);
    try std.testing.expectEqualStrings("completion", plan.completion_name);
    try std.testing.expectEqualStrings("entry", plan.entry_name);
    try std.testing.expectEqualStrings("completed", plan.completion_result_name);
}

test "bounded read-directory plan records two statically visible reads" {
    const source =
        \\read_directory = @host("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.read-directory", (Dir) -> Tuple<Stream<DirectoryEntry>, Future<Result<nil, DirectoryError>>>)
        \\async run(dir Dir) -> nil {
        \\    handles Tuple<Stream<DirectoryEntry>, Future<Result<nil, DirectoryError>>> = read_directory(dir)
        \\    reader Stream<DirectoryEntry> = @get(handles, 0)
        \\    completion Future<Result<nil, DirectoryError>> = @get(handles, 1)
        \\    pending_1 Future<Result<DirectoryEntry, nil>> = @next(reader)
        \\    entry_1 Result<DirectoryEntry, nil> = await(pending_1)
        \\    _ = entry_1
        \\    pending_2 Future<Result<DirectoryEntry, nil>> = @next(reader)
        \\    entry_2 Result<DirectoryEntry, nil> = await(pending_2)
        \\    _ = entry_2
        \\    completed Result<nil, DirectoryError> = await(completion)
        \\    _ = completed
        \\    return
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const plan = try ReadDirectoryPlan.analyze(tokens, registry) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 2), plan.read_count);
}

test "bounded read-directory plan records three reads including EOF probe" {
    const source =
        \\read_directory = @host("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.read-directory", (Dir) -> Tuple<Stream<DirectoryEntry>, Future<Result<nil, DirectoryError>>>)
        \\async run(dir Dir) -> nil {
        \\    handles Tuple<Stream<DirectoryEntry>, Future<Result<nil, DirectoryError>>> = read_directory(dir)
        \\    reader Stream<DirectoryEntry> = @get(handles, 0)
        \\    completion Future<Result<nil, DirectoryError>> = @get(handles, 1)
        \\    pending_1 Future<Result<DirectoryEntry, nil>> = @next(reader)
        \\    entry_1 Result<DirectoryEntry, nil> = await(pending_1)
        \\    _ = entry_1
        \\    pending_2 Future<Result<DirectoryEntry, nil>> = @next(reader)
        \\    entry_2 Result<DirectoryEntry, nil> = await(pending_2)
        \\    _ = entry_2
        \\    pending_3 Future<Result<DirectoryEntry, nil>> = @next(reader)
        \\    entry_3 Result<DirectoryEntry, nil> = await(pending_3)
        \\    _ = entry_3
        \\    completed Result<nil, DirectoryError> = await(completion)
        \\    _ = completed
        \\    return
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const plan = try ReadDirectoryPlan.analyze(tokens, registry) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 3), plan.read_count);
}

test "bounded read-directory plan rejects a fourth statically visible read" {
    const source =
        \\read_directory = @host("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.read-directory", (Dir) -> Tuple<Stream<DirectoryEntry>, Future<Result<nil, DirectoryError>>>)
        \\async run(dir Dir) -> nil {
        \\    handles Tuple<Stream<DirectoryEntry>, Future<Result<nil, DirectoryError>>> = read_directory(dir)
        \\    reader Stream<DirectoryEntry> = @get(handles, 0)
        \\    completion Future<Result<nil, DirectoryError>> = @get(handles, 1)
        \\    pending_1 Future<Result<DirectoryEntry, nil>> = @next(reader)
        \\    entry_1 Result<DirectoryEntry, nil> = await(pending_1)
        \\    _ = entry_1
        \\    pending_2 Future<Result<DirectoryEntry, nil>> = @next(reader)
        \\    entry_2 Result<DirectoryEntry, nil> = await(pending_2)
        \\    _ = entry_2
        \\    pending_3 Future<Result<DirectoryEntry, nil>> = @next(reader)
        \\    entry_3 Result<DirectoryEntry, nil> = await(pending_3)
        \\    _ = entry_3
        \\    pending_4 Future<Result<DirectoryEntry, nil>> = @next(reader)
        \\    entry_4 Result<DirectoryEntry, nil> = await(pending_4)
        \\    _ = entry_4
        \\    completed Result<nil, DirectoryError> = await(completion)
        \\    _ = completed
        \\    return
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    try std.testing.expectError(error.UnsupportedP3WasiReadDirectoryComponent, ReadDirectoryPlan.analyze(tokens, registry));
}

test "read-directory plan accepts a second entry read" {
    const source =
        \\read_directory = @host("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.read-directory", (Dir) -> Tuple<Stream<DirectoryEntry>, Future<Result<nil, DirectoryError>>>)
        \\async run(dir Dir) -> nil {
        \\    handles Tuple<Stream<DirectoryEntry>, Future<Result<nil, DirectoryError>>> = read_directory(dir)
        \\    reader Stream<DirectoryEntry> = @get(handles, 0)
        \\    completion Future<Result<nil, DirectoryError>> = @get(handles, 1)
        \\    pending Future<Result<DirectoryEntry, nil>> = @next(reader)
        \\    entry Result<DirectoryEntry, nil> = await(pending)
        \\    _ = entry
        \\    pending_2 Future<Result<DirectoryEntry, nil>> = @next(reader)
        \\    entry_2 Result<DirectoryEntry, nil> = await(pending_2)
        \\    _ = entry_2
        \\    completed Result<nil, DirectoryError> = await(completion)
        \\    _ = completed
        \\    return
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const plan = try ReadDirectoryPlan.analyze(tokens, registry) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 2), plan.read_count);
}

test "read-directory plan rejects a loop around the fixed read" {
    const source =
        \\read_directory = @host("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.read-directory", (Dir) -> Tuple<Stream<DirectoryEntry>, Future<Result<nil, DirectoryError>>>)
        \\async run(dir Dir) -> nil {
        \\    loop {
        \\        handles Tuple<Stream<DirectoryEntry>, Future<Result<nil, DirectoryError>>> = read_directory(dir)
        \\    }
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    try std.testing.expectError(error.UnsupportedP3WasiReadDirectoryComponent, ReadDirectoryPlan.analyze(tokens, registry));
}

test "read-directory plan rejects an unregistered descriptor" {
    const source =
        \\read_directory = @host("do:filesystem/types@0.3.0", "descriptor.read-directory", (Dir) -> Tuple<Stream<DirectoryEntry>, Future<Result<nil, DirectoryError>>>)
        \\async run(dir Dir) -> nil {
        \\    return
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    try std.testing.expect((try ReadDirectoryPlan.analyze(tokens, registry)) == null);
}

test "read-directory plan rejects a payload-bearing completion" {
    const source =
        \\read_directory = @host("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.read-directory", (Dir) -> Tuple<Stream<DirectoryEntry>, Future<Result<DirectoryEntry, DirectoryError>>>)
        \\async run(dir Dir) -> nil {
        \\    return
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    try std.testing.expect((try ReadDirectoryPlan.analyze(tokens, registry)) == null);
}

test "read-directory emitter preserves the pinned record ABI and one read" {
    const source =
        \\read_directory = @host("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.read-directory", (Dir) -> Tuple<Stream<DirectoryEntry>, Future<Result<nil, DirectoryError>>>)
        \\async run(dir Dir) -> nil {
        \\    handles Tuple<Stream<DirectoryEntry>, Future<Result<nil, DirectoryError>>> = read_directory(dir)
        \\    reader Stream<DirectoryEntry> = @get(handles, 0)
        \\    completion Future<Result<nil, DirectoryError>> = @get(handles, 1)
        \\    pending Future<Result<DirectoryEntry, nil>> = @next(reader)
        \\    entry Result<DirectoryEntry, nil> = await(pending)
        \\    _ = entry
        \\    completed Result<nil, DirectoryError> = await(completion)
        \\    _ = completed
        \\    return
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lower][method]descriptor.read-directory") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lower][stream-read-0][method]descriptor.read-directory") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lower][future-read-1][method]descriptor.read-directory") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[future-drop-readable-1][method]descriptor.read-directory") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "directory-entry") != null);
    try std.testing.expectEqual(@as(usize, 1), count_occurrences(wat, "call $stream-read"));
    try std.testing.expectEqual(@as(usize, 1), count_occurrences(wat, "call $future-read"));

    const wit = try emit_component_wit(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "record directory-entry") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "read-directory: async func()") != null);
}

test "bounded read-directory emitter reuses one stream read site with a counter" {
    const source =
        \\read_directory = @host("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.read-directory", (Dir) -> Tuple<Stream<DirectoryEntry>, Future<Result<nil, DirectoryError>>>)
        \\Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
        \\DirectoryEntry = @wasi_record("filesystem/types/directory-entry", { .type i32, .name text })
        \\DirectoryError error = Io | NoEntry | NotDirectory
        \\async run_bounded(dir Dir) -> nil {
        \\    handles Tuple<Stream<DirectoryEntry>, Future<Result<nil, DirectoryError>>> = read_directory(dir)
        \\    reader Stream<DirectoryEntry> = @get(handles, 0)
        \\    completion Future<Result<nil, DirectoryError>> = @get(handles, 1)
        \\    pending_1 Future<Result<DirectoryEntry, nil>> = @next(reader)
        \\    entry_1 Result<DirectoryEntry, nil> = await(pending_1)
        \\    _ = entry_1
        \\    pending_2 Future<Result<DirectoryEntry, nil>> = @next(reader)
        \\    entry_2 Result<DirectoryEntry, nil> = await(pending_2)
        \\    _ = entry_2
        \\    completed Result<nil, DirectoryError> = await(completion)
        \\    _ = completed
        \\    return
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; bounded remaining reads") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; record-layout directory-entry: type@0 name-ptr@4 name-len@8") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.sub") != null);
    try std.testing.expectEqual(@as(usize, 1), count_occurrences(wat, "call $stream-read"));
}

fn count_occurrences(haystack: []const u8, needle: []const u8) usize {
    if (needle.len == 0) return 0;
    var count: usize = 0;
    var pos: usize = 0;
    while (std.mem.indexOfPos(u8, haystack, pos, needle)) |found| {
        count += 1;
        pos = found + needle.len;
    }
    return count;
}
