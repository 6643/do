const std = @import("std");
const generated_text = @import("codegen_text.zig");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const p3_async_manifest = @import("p3_async_manifest.zig");
const sema_tokens = @import("sema_tokens.zig");

const find_matching = sema_tokens.find_matching;
const string_token_body = sema_tokens.string_token_body;
const tok_eq = sema_tokens.tok_eq;

pub const Error = error{UnsupportedP3WasiFilesystemWriteViaStreamComponent};

const locator = "wasi:filesystem/types@0.3.0-rc-2025-09-16";
const member = "descriptor.write-via-stream";
const completion_type = "Result<nil,FileError>";
const completion_future_type = "Future<Result<nil,FileError>>";
const write_result_type = "Result<nil,StreamError>";
const write_future_type = "Future<Result<nil,StreamError>>";

pub const WriteViaStreamPlan = struct {
    export_name: []const u8,
    descriptor: p3_async_manifest.Descriptor,
    file_name: []const u8,
    offset_name: []const u8,
    writer_name: []const u8,
    value_name: []const u8,
};

pub fn emit_component_wat(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph,
) ![]u8 {
    _ = program;
    _ = module_graph;
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    const plan = try analyze(tokens, registry);
    const shape = switch (p3_async_manifest.lowering_shape(plan.descriptor) orelse return error.UnsupportedP3WasiFilesystemWriteViaStreamComponent) {
        .filesystem_byte_stream_writer => |value| value,
        else => return error.UnsupportedP3WasiFilesystemWriteViaStreamComponent,
    };
    var wat = try generated_text.alloc_block(allocator, 0, @embedFile("wasi_filesystem_write_via_stream_component_template.wat"));
    errdefer allocator.free(wat);
    const replacements = [_][2][]const u8{
        .{ "[method-module]", plan.descriptor.canonical.async_import_module },
        .{ "[method-name]", shape.method.import_name },
        .{ "[stream-new-name]", shape.stream.new.import_name },
        .{ "[stream-cancel-read-name]", shape.stream.cancel_read.import_name },
        .{ "[stream-cancel-write-name]", shape.stream.cancel_write.import_name },
        .{ "[stream-drop-readable-name]", shape.stream.drop_readable.import_name },
        .{ "[stream-drop-writable-name]", shape.stream.drop_writable.import_name },
        .{ "[stream-read-name]", shape.stream.read.import_name },
        .{ "[stream-write-name]", shape.stream.write.import_name },
        .{ "[resource-drop-name]", shape.resource_drop_import },
        .{ "[run-lift]", "[async-lift]wasi:filesystem/probe@0.3.0-rc-2025-09-16#run" },
        .{ "[run-callback]", "[callback][async-lift]wasi:filesystem/probe@0.3.0-rc-2025-09-16#run" },
        .{ "[cancel-lift]", "[async-lift]wasi:filesystem/probe@0.3.0-rc-2025-09-16#cancel" },
        .{ "[cancel-callback]", "[callback][async-lift]wasi:filesystem/probe@0.3.0-rc-2025-09-16#cancel" },
        .{ "[task-return-run]", "[task-return]run" },
        .{ "[task-return-cancel]", "[task-return]cancel" },
    };
    for (replacements) |replacement| wat = try replace_and_free(allocator, wat, replacement[0], replacement[1]);
    return wat;
}

pub fn emit_component_wit(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]u8 {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    _ = try analyze(tokens, registry);
    return generated_text.alloc_block(allocator, 0,
        \\package wasi:filesystem@0.3.0-rc-2025-09-16;
        \\
        \\interface types {
        \\  enum error-code { access, already, bad-descriptor, busy, deadlock, quota, exist, file-too-large, illegal-byte-sequence, in-progress, interrupted, invalid, io, is-directory, loop, too-many-links, message-size, name-too-long, no-device, no-entry, no-lock, insufficient-memory, insufficient-space, not-directory, not-empty, not-recoverable, unsupported, no-tty, no-such-device, overflow, not-permitted, pipe, read-only, invalid-seek, text-file-busy, cross-device }
        \\  resource descriptor {
        \\    write-via-stream: async func(data: stream<u8>, offset: u64) -> result<_, error-code>;
        \\  }
        \\}
        \\
        \\interface probe {
        \\  use types.{descriptor, error-code};
        \\  run: async func(file: own<descriptor>, offset: u64);
        \\  cancel: async func();
        \\}
        \\
        \\world write-via-stream-probe {
        \\  import types;
        \\  export probe;
        \\}
        \\
    );
}

fn replace_and_free(allocator: std.mem.Allocator, input: []u8, needle: []const u8, replacement: []const u8) ![]u8 {
    const output = try replace_all(allocator, input, needle, replacement);
    allocator.free(input);
    return output;
}

fn replace_all(allocator: std.mem.Allocator, input: []const u8, needle: []const u8, replacement: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    var rest = input;
    while (std.mem.indexOf(u8, rest, needle)) |idx| {
        try out.appendSlice(allocator, rest[0..idx]);
        try out.appendSlice(allocator, replacement);
        rest = rest[idx + needle.len ..];
    }
    try out.appendSlice(allocator, rest);
    return out.toOwnedSlice(allocator);
}

pub fn analyze(tokens: []const lexer.Token, registry: p3_async_manifest.Registry) Error!WriteViaStreamPlan {
    const host = find_host(tokens, registry) orelse return error.UnsupportedP3WasiFilesystemWriteViaStreamComponent;
    const function = find_run_function(tokens) orelse return error.UnsupportedP3WasiFilesystemWriteViaStreamComponent;
    var pos = function.body_start;

    const stream = parse_stream_acquisition(tokens, pos, function.body_end) orelse
        return error.UnsupportedP3WasiFilesystemWriteViaStreamComponent;
    pos = stream.next_idx;
    pos = parse_defer_close(tokens, pos, function.body_end, stream.writer_name) orelse
        return error.UnsupportedP3WasiFilesystemWriteViaStreamComponent;
    const method = parse_method_call(tokens, pos, function.body_end, host.name, function.file_name, stream.writer_name, function.offset_name) orelse
        return error.UnsupportedP3WasiFilesystemWriteViaStreamComponent;
    pos = method.next_idx;
    const value = parse_value(tokens, pos, function.body_end) orelse
        return error.UnsupportedP3WasiFilesystemWriteViaStreamComponent;
    pos = value.next_idx;
    const write = parse_write_call(tokens, pos, function.body_end, stream.writer_name, value.name) orelse
        return error.UnsupportedP3WasiFilesystemWriteViaStreamComponent;
    pos = write.next_idx;
    const write_result = parse_await_binding(tokens, pos, function.body_end, write_result_type, write.pending_name) orelse
        return error.UnsupportedP3WasiFilesystemWriteViaStreamComponent;
    pos = write_result.next_idx;
    pos = parse_discard(tokens, pos, function.body_end, write_result.name) orelse
        return error.UnsupportedP3WasiFilesystemWriteViaStreamComponent;
    const completion = parse_await_binding(tokens, pos, function.body_end, completion_type, method.name) orelse
        return error.UnsupportedP3WasiFilesystemWriteViaStreamComponent;
    pos = completion.next_idx;
    pos = parse_discard(tokens, pos, function.body_end, completion.name) orelse
        return error.UnsupportedP3WasiFilesystemWriteViaStreamComponent;
    if (pos + 1 != function.body_end or !tok_eq(tokens[pos], "return"))
        return error.UnsupportedP3WasiFilesystemWriteViaStreamComponent;

    return .{
        .export_name = function.name,
        .descriptor = host.descriptor,
        .file_name = function.file_name,
        .offset_name = function.offset_name,
        .writer_name = stream.writer_name,
        .value_name = value.name,
    };
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
    writer_name: []const u8 = "",
    next_idx: usize,
};

fn find_host(tokens: []const lexer.Token, registry: p3_async_manifest.Registry) ?Host {
    var found: ?Host = null;
    var idx: usize = 0;
    while (idx + 9 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "=") or !tok_eq(tokens[idx + 2], "@") or
            !tok_eq(tokens[idx + 3], "host_async_func") or !tok_eq(tokens[idx + 4], "(") or
            tokens[idx + 5].kind != .string or !tok_eq(tokens[idx + 6], ",") or tokens[idx + 7].kind != .string or
            !tok_eq(tokens[idx + 8], ",") or !tok_eq(tokens[idx + 9], "(")) continue;
        const host_close = find_matching(tokens, idx + 4, "(", ")") catch continue;
        if (!compact_equals(tokens, idx + 9, host_close + 1, "(File,StreamWriter<u8>,u64)->Result<nil,FileError>)")) continue;
        const host_locator = string_token_body(tokens[idx + 5].lexeme) orelse continue;
        const host_member = string_token_body(tokens[idx + 7].lexeme) orelse continue;
        if (!std.mem.eql(u8, host_locator, locator) or !std.mem.eql(u8, host_member, member)) continue;
        const descriptor = registry.find(host_locator, host_member) orelse continue;
        switch (p3_async_manifest.lowering_shape(descriptor) orelse continue) {
            .filesystem_byte_stream_writer => {},
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
    while (idx + 8 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "(") or
            (idx > 0 and tok_eq(tokens[idx - 1], "async"))) continue;
        const params_close = find_matching(tokens, idx + 1, "(", ")") catch continue;
        if (params_close != idx + 7 or tokens[idx + 2].kind != .ident or !tok_eq(tokens[idx + 3], "File") or
            tokens[idx + 5].kind != .ident or !tok_eq(tokens[idx + 6], "u64") or
            !tok_eq(tokens[params_close + 1], "-") or !tok_eq(tokens[params_close + 2], ">") or
            !tok_eq(tokens[params_close + 3], "nil")) continue;
        const body_open = params_close + 4;
        if (!tok_eq(tokens[body_open], "{")) continue;
        const body_end = find_matching(tokens, body_open, "{", "}") catch continue;
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

fn parse_stream_acquisition(tokens: []const lexer.Token, idx: usize, end_idx: usize) ?Binding {
    if (idx + 18 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "StreamReader") or
        !tok_eq(tokens[idx + 2], "<") or !tok_eq(tokens[idx + 3], "u8") or !tok_eq(tokens[idx + 4], ">") or
        !tok_eq(tokens[idx + 5], ",") or tokens[idx + 6].kind != .ident or !tok_eq(tokens[idx + 7], "StreamWriter") or
        !tok_eq(tokens[idx + 8], "<") or !tok_eq(tokens[idx + 9], "u8") or !tok_eq(tokens[idx + 10], ">") or
        !tok_eq(tokens[idx + 11], "=") or !tok_eq(tokens[idx + 12], "new_stream") or !tok_eq(tokens[idx + 13], "<") or
        !tok_eq(tokens[idx + 14], "u8") or !tok_eq(tokens[idx + 15], ">") or !tok_eq(tokens[idx + 16], "(") or
        !tok_eq(tokens[idx + 17], "1") or !tok_eq(tokens[idx + 18], ")")) return null;
    return .{ .name = tokens[idx].lexeme, .writer_name = tokens[idx + 6].lexeme, .next_idx = idx + 19 };
}

fn parse_defer_close(tokens: []const lexer.Token, idx: usize, end_idx: usize, writer_name: []const u8) ?usize {
    if (idx + 4 >= end_idx or !tok_eq(tokens[idx], "defer") or !tok_eq(tokens[idx + 1], "close") or
        !tok_eq(tokens[idx + 2], "(") or tokens[idx + 3].kind != .ident or
        !std.mem.eql(u8, tokens[idx + 3].lexeme, writer_name) or !tok_eq(tokens[idx + 4], ")")) return null;
    return idx + 5;
}

fn parse_method_call(tokens: []const lexer.Token, idx: usize, end_idx: usize, host_name: []const u8, file_name: []const u8, writer_name: []const u8, offset_name: []const u8) ?Binding {
    if (idx + 12 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "Future") or !tok_eq(tokens[idx + 2], "<")) return null;
    const type_end = find_matching(tokens, idx + 2, "<", ">") catch return null;

    if (!compact_equals(tokens, idx + 1, type_end + 1, completion_future_type) or !tok_eq(tokens[type_end + 1], "=") or
        tokens[type_end + 2].kind != .ident or !std.mem.eql(u8, tokens[type_end + 2].lexeme, host_name) or
        !tok_eq(tokens[type_end + 3], "(") or !same_ident(tokens, type_end + 4, file_name) or !tok_eq(tokens[type_end + 5], ",") or
        !same_ident(tokens, type_end + 6, writer_name) or !tok_eq(tokens[type_end + 7], ",") or
        !same_ident(tokens, type_end + 8, offset_name) or !tok_eq(tokens[type_end + 9], ")")) return null;
    return .{ .name = tokens[idx].lexeme, .next_idx = type_end + 10 };
}

fn parse_value(tokens: []const lexer.Token, idx: usize, end_idx: usize) ?Binding {
    if (idx + 3 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "u8") or
        !tok_eq(tokens[idx + 2], "=") or tokens[idx + 3].kind != .number) return null;
    return .{ .name = tokens[idx].lexeme, .next_idx = idx + 4 };
}

fn parse_write_call(tokens: []const lexer.Token, idx: usize, end_idx: usize, writer_name: []const u8, value_name: []const u8) ?struct { pending_name: []const u8, next_idx: usize } {
    if (idx + 10 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "Future") or !tok_eq(tokens[idx + 2], "<")) return null;
    const type_end = find_matching(tokens, idx + 2, "<", ">") catch return null;
    if (!compact_equals(tokens, idx + 1, type_end + 1, write_future_type) or !tok_eq(tokens[type_end + 1], "=") or
        !same_ident(tokens, type_end + 2, writer_name) or !tok_eq(tokens[type_end + 3], "(") or
        !same_ident(tokens, type_end + 4, value_name) or !tok_eq(tokens[type_end + 5], ")")) return null;
    return .{ .pending_name = tokens[idx].lexeme, .next_idx = type_end + 6 };
}

fn parse_await_binding(tokens: []const lexer.Token, idx: usize, end_idx: usize, type_name: []const u8, pending_name: []const u8) ?struct { name: []const u8, next_idx: usize } {
    if (idx + 7 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "Result") or !tok_eq(tokens[idx + 2], "<")) return null;
    const type_end = find_matching(tokens, idx + 2, "<", ">") catch return null;
    if (!compact_equals(tokens, idx + 1, type_end + 1, type_name) or !tok_eq(tokens[type_end + 1], "=") or
        !tok_eq(tokens[type_end + 2], "@") or !tok_eq(tokens[type_end + 3], "await") or
        !tok_eq(tokens[type_end + 4], "(") or !same_ident(tokens, type_end + 5, pending_name) or
        !tok_eq(tokens[type_end + 6], ")")) return null;
    return .{ .name = tokens[idx].lexeme, .next_idx = type_end + 7 };
}

fn parse_discard(tokens: []const lexer.Token, idx: usize, end_idx: usize, name: []const u8) ?usize {
    if (idx + 2 >= end_idx or !tok_eq(tokens[idx], "_") or !tok_eq(tokens[idx + 1], "=") or
        !same_ident(tokens, idx + 2, name)) return null;
    return idx + 3;
}

fn compact_equals(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, expected: []const u8) bool {
    var pos: usize = 0;
    var idx = start_idx;
    while (idx < end_idx) : (idx += 1) {
        const lexeme = tokens[idx].lexeme;
        if (pos + lexeme.len > expected.len or !std.mem.eql(u8, expected[pos .. pos + lexeme.len], lexeme)) return false;
        pos += lexeme.len;
    }
    return pos == expected.len;
}

fn same_ident(tokens: []const lexer.Token, idx: usize, name: []const u8) bool {
    return idx < tokens.len and tokens[idx].kind == .ident and std.mem.eql(u8, tokens[idx].lexeme, name);
}

const positive_source =
    \\write_via_stream = @host_async_func("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.write-via-stream", (File, StreamWriter<u8>, u64) -> Result<nil, FileError>)
    \\File = @wasi_resource("filesystem/types/descriptor", { .id i64 })
    \\FileError error = Io | NoEntry
    \\run(file File, offset u64) -> nil {
    \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
    \\    defer close(writer)
    \\    pending Future<Result<nil, FileError>> = write_via_stream(file, writer, offset)
    \\    first u8 = 65
    \\    write_pending Future<Result<nil, StreamError>> = writer(first)
    \\    write_result Result<nil, StreamError> = @await(write_pending)
    \\    _ = write_result
    \\    completed Result<nil, FileError> = @await(pending)
    \\    _ = completed
    \\    return
    \\}
    \\start() {}
;

test "filesystem write-via-stream plan admits the bounded source contract" {
    const tokens = try lexer.tokenize(std.testing.allocator, positive_source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const plan = try analyze(tokens, registry);
    try std.testing.expectEqualStrings("run", plan.export_name);
    try std.testing.expectEqualStrings("file", plan.file_name);
    try std.testing.expectEqualStrings("offset", plan.offset_name);
    try std.testing.expectEqualStrings("writer", plan.writer_name);
    try std.testing.expectEqualStrings("first", plan.value_name);
}

test "filesystem write-via-stream plan rejects a non-byte writer" {
    const source = std.mem.replaceOwned(u8, std.testing.allocator, positive_source, "StreamWriter<u8>", "StreamWriter<u32>") catch unreachable;
    defer std.testing.allocator.free(source);
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    try std.testing.expectError(error.UnsupportedP3WasiFilesystemWriteViaStreamComponent, analyze(tokens, registry));
}

test "filesystem write-via-stream plan requires deferred writer close" {
    const source = std.mem.replaceOwned(u8, std.testing.allocator, positive_source, "    defer close(writer)\n", "") catch unreachable;
    defer std.testing.allocator.free(source);
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    try std.testing.expectError(error.UnsupportedP3WasiFilesystemWriteViaStreamComponent, analyze(tokens, registry));
}

test "filesystem write-via-stream emitter preserves the measured lifecycle imports" {
    const tokens = try lexer.tokenize(std.testing.allocator, positive_source);
    defer std.testing.allocator.free(tokens);
    const wat = try emit_component_wat(std.testing.allocator, undefined, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "\"[async-lower][method]descriptor.write-via-stream\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "\"[stream-new-0][method]descriptor.write-via-stream\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "\"[async-lower][stream-write-0][method]descriptor.write-via-stream\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "\"[stream-drop-writable-0][method]descriptor.write-via-stream\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "\"[resource-drop]descriptor\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[filesystem-write-via-stream]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "stream.forward") == null);
}

test "filesystem write-via-stream WIT exposes the descriptor method and cancellation" {
    const tokens = try lexer.tokenize(std.testing.allocator, positive_source);
    defer std.testing.allocator.free(tokens);
    const wit = try emit_component_wit(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "write-via-stream: async func(data: stream<u8>, offset: u64)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "run: async func(file: own<descriptor>, offset: u64);") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "cancel: async func();") != null);
}
