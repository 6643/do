const std = @import("std");
const build_diag = @import("../build/diag.zig");

pub const RequestId = union(enum) {
    number: i64,
    string: []const u8,
    null,
};

pub fn writeInitializeResponse(
    allocator: std.mem.Allocator,
    writer: anytype,
    id: RequestId,
) !void {
    var body = std.Io.Writer.Allocating.init(allocator);
    defer body.deinit();

    const body_writer = &body.writer;
    try body_writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
    try writeRequestId(body_writer, id);
    try body_writer.writeAll(",\"result\":{\"capabilities\":{\"textDocumentSync\":2},\"serverInfo\":{\"name\":\"do-lsp\"}}}");

    try writeFrame(writer, body_writer.buffered());
}

pub fn writeShutdownResponse(
    allocator: std.mem.Allocator,
    writer: anytype,
    id: RequestId,
) !void {
    var body = std.Io.Writer.Allocating.init(allocator);
    defer body.deinit();

    const body_writer = &body.writer;
    try body_writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
    try writeRequestId(body_writer, id);
    try body_writer.writeAll(",\"result\":null}");

    try writeFrame(writer, body_writer.buffered());
}

pub fn writePublishDiagnostics(
    allocator: std.mem.Allocator,
    writer: anytype,
    uri: []const u8,
    diagnostics: []const build_diag.CompileDiagnostic,
) !void {
    var body = std.Io.Writer.Allocating.init(allocator);
    defer body.deinit();

    const body_writer = &body.writer;
    try body_writer.writeAll("{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/publishDiagnostics\",\"params\":{\"uri\":");
    try writeJsonString(body_writer, uri);
    try body_writer.writeAll(",\"diagnostics\":[");
    for (diagnostics, 0..) |diagnostic, idx| {
        if (idx != 0) try body_writer.writeAll(",");
        try writeDiagnostic(body_writer, diagnostic);
    }
    try body_writer.writeAll("]}}");

    try writeFrame(writer, body_writer.buffered());
}

fn writeFrame(writer: anytype, body: []const u8) !void {
    try writer.print("Content-Length: {d}\r\n\r\n", .{body.len});
    try writer.writeAll(body);
}

fn writeRequestId(writer: anytype, id: RequestId) !void {
    switch (id) {
        .number => |value| try writer.print("{d}", .{value}),
        .string => |value| try writeJsonString(writer, value),
        .null => try writer.writeAll("null"),
    }
}

fn writeDiagnostic(writer: anytype, diagnostic: build_diag.CompileDiagnostic) !void {
    const start_line = zeroBased(diagnostic.loc.line);
    const start_character = zeroBased(diagnostic.loc.col);
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
    try writeJsonString(writer, diagnostic.code);
    try writer.writeAll(",\"message\":");
    try writeJsonString(writer, diagnostic.message);
    try writer.writeAll(",\"source\":\"do\"}");
}

fn writeJsonString(writer: anytype, value: []const u8) !void {
    try std.json.Stringify.value(value, .{}, writer);
}

fn zeroBased(value: usize) usize {
    return if (value == 0) 0 else value - 1;
}

test "writeResponse writes content length framed initialize response" {
    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    try writeInitializeResponse(std.testing.allocator, &out.writer, .{ .number = 1 });

    const bytes = out.writer.buffered();
    try std.testing.expect(std.mem.startsWith(u8, bytes, "Content-Length: "));
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\r\n\r\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"capabilities\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"textDocumentSync\"") != null);
}

test "writePublishDiagnostics emits zero based LSP range" {
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
    try writePublishDiagnostics(
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
