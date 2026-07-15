const std = @import("std");
const build_diag = @import("../build/diag.zig");
const semantic_tokens = @import("semantic_tokens.zig");

pub const Position = struct {
    line: usize,
    character: usize,
};

pub const Range = struct {
    start: Position,
    end: Position,
};

pub const TextEdit = struct {
    range: Range,
    new_text: []const u8,
};

pub const Location = struct {
    uri: []const u8,
    range: Range,
};

pub const CompletionItemKind = enum {
    function,
    type_name,
    field,
    variable,
};

pub const CompletionItem = struct {
    label: []const u8,
    kind: CompletionItemKind,
    detail: ?[]const u8 = null,
};

pub const RequestId = union(enum) {
    number: i64,
    string: []const u8,
    null,
};

pub fn write_initialize_response(
    allocator: std.mem.Allocator,
    writer: anytype,
    id: RequestId,
) !void {
    var body = std.Io.Writer.Allocating.init(allocator);
    defer body.deinit();

    const body_writer = &body.writer;
    try body_writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
    try write_request_id(body_writer, id);
    try body_writer.writeAll(",\"result\":{\"capabilities\":{\"textDocumentSync\":2,\"documentFormattingProvider\":true,\"hoverProvider\":true,\"completionProvider\":{\"triggerCharacters\":[\".\"]},\"definitionProvider\":true,\"semanticTokensProvider\":{\"legend\":{\"tokenTypes\":");
    try write_json_string_array(body_writer, &semantic_tokens.legendTokenTypes);
    try body_writer.writeAll(",\"tokenModifiers\":");
    try write_json_string_array(body_writer, &semantic_tokens.legendTokenModifiers);
    try body_writer.writeAll("},\"full\":true}},\"serverInfo\":{\"name\":\"do-lsp\"}}}");

    try write_frame(writer, body_writer.buffered());
}

pub fn write_shutdown_response(
    allocator: std.mem.Allocator,
    writer: anytype,
    id: RequestId,
) !void {
    var body = std.Io.Writer.Allocating.init(allocator);
    defer body.deinit();

    const body_writer = &body.writer;
    try body_writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
    try write_request_id(body_writer, id);
    try body_writer.writeAll(",\"result\":null}");

    try write_frame(writer, body_writer.buffered());
}

pub fn write_publish_diagnostics(
    allocator: std.mem.Allocator,
    writer: anytype,
    uri: []const u8,
    diagnostics: []const build_diag.CompileDiagnostic,
) !void {
    var body = std.Io.Writer.Allocating.init(allocator);
    defer body.deinit();

    const body_writer = &body.writer;
    try body_writer.writeAll("{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/publishDiagnostics\",\"params\":{\"uri\":");
    try write_json_string(body_writer, uri);
    try body_writer.writeAll(",\"diagnostics\":[");
    for (diagnostics, 0..) |diagnostic, idx| {
        if (idx != 0) try body_writer.writeAll(",");
        try write_diagnostic(body_writer, diagnostic);
    }
    try body_writer.writeAll("]}}");

    try write_frame(writer, body_writer.buffered());
}

pub fn write_text_edits_response(
    allocator: std.mem.Allocator,
    writer: anytype,
    id: RequestId,
    edits: []const TextEdit,
) !void {
    var body = std.Io.Writer.Allocating.init(allocator);
    defer body.deinit();

    const body_writer = &body.writer;
    try body_writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
    try write_request_id(body_writer, id);
    try body_writer.writeAll(",\"result\":[");
    for (edits, 0..) |edit, idx| {
        if (idx != 0) try body_writer.writeAll(",");
        try write_text_edit(body_writer, edit);
    }
    try body_writer.writeAll("]}");

    try write_frame(writer, body_writer.buffered());
}

pub fn write_semantic_tokens_response(
    allocator: std.mem.Allocator,
    writer: anytype,
    id: RequestId,
    data: []const u32,
) !void {
    var body = std.Io.Writer.Allocating.init(allocator);
    defer body.deinit();

    const body_writer = &body.writer;
    try body_writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
    try write_request_id(body_writer, id);
    try body_writer.writeAll(",\"result\":{\"data\":[");
    for (data, 0..) |value, idx| {
        if (idx != 0) try body_writer.writeAll(",");
        try body_writer.print("{d}", .{value});
    }
    try body_writer.writeAll("]}}");

    try write_frame(writer, body_writer.buffered());
}

pub fn write_hover_response(
    allocator: std.mem.Allocator,
    writer: anytype,
    id: RequestId,
    contents: ?[]const u8,
) !void {
    var body = std.Io.Writer.Allocating.init(allocator);
    defer body.deinit();

    const body_writer = &body.writer;
    try body_writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
    try write_request_id(body_writer, id);
    if (contents) |value| {
        try body_writer.writeAll(",\"result\":{\"contents\":{\"kind\":\"plaintext\",\"value\":");
        try write_json_string(body_writer, value);
        try body_writer.writeAll("}}}");
    } else {
        try body_writer.writeAll(",\"result\":null");
    }
    try body_writer.writeAll("}");

    try write_frame(writer, body_writer.buffered());
}

pub fn write_completion_response(
    allocator: std.mem.Allocator,
    writer: anytype,
    id: RequestId,
    items: []const CompletionItem,
) !void {
    var body = std.Io.Writer.Allocating.init(allocator);
    defer body.deinit();

    const body_writer = &body.writer;
    try body_writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
    try write_request_id(body_writer, id);
    try body_writer.writeAll(",\"result\":[");
    for (items, 0..) |item, idx| {
        if (idx != 0) try body_writer.writeAll(",");
        try write_completion_item(body_writer, item);
    }
    try body_writer.writeAll("]}");

    try write_frame(writer, body_writer.buffered());
}

pub fn write_definition_response(
    allocator: std.mem.Allocator,
    writer: anytype,
    id: RequestId,
    location: ?Location,
) !void {
    var body = std.Io.Writer.Allocating.init(allocator);
    defer body.deinit();

    const body_writer = &body.writer;
    try body_writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
    try write_request_id(body_writer, id);
    if (location) |value| {
        try body_writer.writeAll(",\"result\":");
        try write_location(body_writer, value);
    } else {
        try body_writer.writeAll(",\"result\":null");
    }
    try body_writer.writeAll("}");

    try write_frame(writer, body_writer.buffered());
}

fn write_frame(writer: anytype, body: []const u8) !void {
    try writer.print("Content-Length: {d}\r\n\r\n", .{body.len});
    try writer.writeAll(body);
}

fn write_request_id(writer: anytype, id: RequestId) !void {
    switch (id) {
        .number => |value| try writer.print("{d}", .{value}),
        .string => |value| try write_json_string(writer, value),
        .null => try writer.writeAll("null"),
    }
}

fn write_diagnostic(writer: anytype, diagnostic: build_diag.CompileDiagnostic) !void {
    const start_line = zero_based(diagnostic.loc.line);
    const start_character = zero_based(diagnostic.loc.col);
    const end_character = start_character + 1;

    try writer.writeAll("{\"range\":{\"start\":{\"line\":");
    try writer.print("{d}", .{start_line});
    try writer.writeAll(",\"character\":");
    try writer.print("{d}", .{start_character});
    try writer.writeAll("},\"end\":{\"line\":");
    try writer.print("{d}", .{start_line});
    try writer.writeAll(",\"character\":");
    try writer.print("{d}", .{end_character});
    try writer.writeAll("}},\"severity\":1,\"code\":");
    try write_json_string(writer, diagnostic.code);
    try writer.writeAll(",\"message\":");
    try write_json_string(writer, diagnostic.message);
    try writer.writeAll(",\"source\":\"do\"}");
}

fn write_json_string(writer: anytype, value: []const u8) !void {
    try std.json.Stringify.value(value, .{}, writer);
}

fn write_json_string_array(writer: anytype, values: []const []const u8) !void {
    try writer.writeAll("[");
    for (values, 0..) |value, idx| {
        if (idx != 0) try writer.writeAll(",");
        try write_json_string(writer, value);
    }
    try writer.writeAll("]");
}

fn write_text_edit(writer: anytype, edit: TextEdit) !void {
    try writer.writeAll("{\"range\":");
    try write_range(writer, edit.range);
    try writer.writeAll(",\"newText\":");
    try write_json_string(writer, edit.new_text);
    try writer.writeAll("}");
}

fn write_completion_item(writer: anytype, item: CompletionItem) !void {
    try writer.writeAll("{\"label\":");
    try write_json_string(writer, item.label);
    try writer.writeAll(",\"kind\":");
    try writer.print("{d}", .{completion_item_kind_value(item.kind)});
    if (item.detail) |detail| {
        try writer.writeAll(",\"detail\":");
        try write_json_string(writer, detail);
    }
    try writer.writeAll("}");
}

fn write_location(writer: anytype, location: Location) !void {
    try writer.writeAll("{\"uri\":");
    try write_json_string(writer, location.uri);
    try writer.writeAll(",\"range\":");
    try write_range(writer, location.range);
    try writer.writeAll("}");
}

fn completion_item_kind_value(kind: CompletionItemKind) u8 {
    return switch (kind) {
        .function => 3,
        .field => 5,
        .variable => 6,
        .type_name => 7,
    };
}

fn write_range(writer: anytype, range: Range) !void {
    try writer.writeAll("{\"start\":");
    try write_position(writer, range.start);
    try writer.writeAll(",\"end\":");
    try write_position(writer, range.end);
    try writer.writeAll("}");
}

fn write_position(writer: anytype, position: Position) !void {
    try writer.writeAll("{\"line\":");
    try writer.print("{d}", .{position.line});
    try writer.writeAll(",\"character\":");
    try writer.print("{d}", .{position.character});
    try writer.writeAll("}");
}

fn zero_based(value: usize) usize {
    return if (value == 0) 0 else value - 1;
}

test "writeResponse writes content length framed initialize response" {
    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    try write_initialize_response(std.testing.allocator, &out.writer, .{ .number = 1 });

    const bytes = out.writer.buffered();
    try std.testing.expect(std.mem.startsWith(u8, bytes, "Content-Length: "));
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\r\n\r\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"capabilities\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"textDocumentSync\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"documentFormattingProvider\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"hoverProvider\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"completionProvider\":{\"triggerCharacters\":[\".\"]}") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"definitionProvider\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"semanticTokensProvider\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"tokenTypes\":[\"keyword\",\"type\",\"function\",\"parameter\",\"variable\",\"field\",\"property\",\"string\",\"number\",\"comment\",\"operator\",\"builtin\"]") != null);
}

test "write_hover_response emits plaintext markup content or null" {
    var hit = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer hit.deinit();

    try write_hover_response(std.testing.allocator, &hit.writer, .{ .number = 2 }, "get_title(user User) -> text");

    const hit_bytes = hit.writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, hit_bytes, "\"result\":{\"contents\":{\"kind\":\"plaintext\",\"value\":\"get_title(user User) -> text\"}}") != null);

    var miss = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer miss.deinit();

    try write_hover_response(std.testing.allocator, &miss.writer, .{ .number = 3 }, null);

    const miss_bytes = miss.writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, miss_bytes, "\"result\":null") != null);
}

test "write_completion_response emits completion item array" {
    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    const items = [_]CompletionItem{
        .{
            .label = "get_title",
            .kind = .function,
            .detail = "get_title(user User) -> text",
        },
        .{
            .label = "User",
            .kind = .type_name,
        },
    };

    try write_completion_response(std.testing.allocator, &out.writer, .{ .number = 4 }, &items);

    const bytes = out.writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"result\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "{\"label\":\"get_title\",\"kind\":3,\"detail\":\"get_title(user User) -> text\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "{\"label\":\"User\",\"kind\":7}") != null);
}

test "write_definition_response emits location or null" {
    var hit = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer hit.deinit();

    try write_definition_response(std.testing.allocator, &hit.writer, .{ .number = 5 }, .{
        .uri = "file:///tmp/app.do",
        .range = .{
            .start = .{ .line = 3, .character = 0 },
            .end = .{ .line = 3, .character = 9 },
        },
    });

    const hit_bytes = hit.writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, hit_bytes, "\"result\":{\"uri\":\"file:///tmp/app.do\",\"range\":{\"start\":{\"line\":3,\"character\":0},\"end\":{\"line\":3,\"character\":9}}}") != null);

    var miss = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer miss.deinit();

    try write_definition_response(std.testing.allocator, &miss.writer, .{ .number = 6 }, null);

    const miss_bytes = miss.writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, miss_bytes, "\"result\":null") != null);
}

test "write_publish_diagnostics emits zero based LSP range" {
    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    const diagnostic = build_diag.CompileDiagnostic{
        .path = "mem://bad.do",
        .loc = .{ .line = 3, .col = 5 },
        .code = "InvalidIfHeader",
        .message = "bad if",
        .hint = "use if expr",
        .line_text = "    if",
    };
    try write_publish_diagnostics(
        std.testing.allocator,
        &out.writer,
        "file:///tmp/bad.do",
        &.{diagnostic},
    );

    const bytes = out.writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"method\":\"textDocument/publishDiagnostics\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"line\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"character\":4") != null);
}

test "write_text_edits_response emits formatting edit payload" {
    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    const edit = TextEdit{
        .range = .{
            .start = .{ .line = 0, .character = 0 },
            .end = .{ .line = 2, .character = 1 },
        },
        .new_text = "User {\n    id i32\n}\n",
    };

    try write_text_edits_response(std.testing.allocator, &out.writer, .{ .number = 2 }, &.{edit});

    const bytes = out.writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"result\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"newText\":\"User {\\n    id i32\\n}\\n\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"line\":2") != null);
}

test "write_semantic_tokens_response emits token data payload" {
    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    try write_semantic_tokens_response(std.testing.allocator, &out.writer, .{ .number = 2 }, &.{ 0, 0, 4, 0, 0 });

    const bytes = out.writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"result\":{\"data\":[0,0,4,0,0]}") != null);
}
