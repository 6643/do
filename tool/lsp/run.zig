const std = @import("std");
const cli = @import("../build/cli.zig");
const diag = @import("../build/diag.zig");
const diagnostics = @import("diagnostics.zig");
const env = @import("../env.zig");
const formatter = @import("../fmt/format.zig");
const protocol = @import("protocol.zig");
const semantic_tokens = @import("semantic_tokens.zig");

const max_frame_len = 16 * 1024 * 1024;

pub const Document = struct {
    uri: []const u8,
    source: []const u8,
};

pub const ServerState = struct {
    allocator: std.mem.Allocator,
    dep_root: []const u8,
    documents: std.ArrayList(Document),
    shutdown_requested: bool = false,

    pub fn init(allocator: std.mem.Allocator, dep_root: []const u8) ServerState {
        return .{
            .allocator = allocator,
            .dep_root = dep_root,
            .documents = .empty,
        };
    }

    pub fn deinit(self: *ServerState) void {
        for (self.documents.items) |doc| {
            self.allocator.free(doc.uri);
            self.allocator.free(doc.source);
        }
        self.documents.deinit(self.allocator);
        self.* = .init(self.allocator, self.dep_root);
    }

    pub fn didOpen(self: *ServerState, uri: []const u8, text: []const u8) !void {
        if (self.findDocumentIndex(uri)) |idx| {
            try self.replaceSource(idx, text);
            return;
        }

        const owned_uri = try self.allocator.dupe(u8, uri);
        errdefer self.allocator.free(owned_uri);

        const owned_source = try self.allocator.dupe(u8, text);
        errdefer self.allocator.free(owned_source);

        try self.documents.append(self.allocator, .{
            .uri = owned_uri,
            .source = owned_source,
        });
    }

    pub fn didChange(self: *ServerState, uri: []const u8, text: []const u8) !void {
        const idx = self.findDocumentIndex(uri) orelse {
            try self.didOpen(uri, text);
            return;
        };
        try self.replaceSource(idx, text);
    }

    pub fn didClose(self: *ServerState, uri: []const u8) !void {
        const idx = self.findDocumentIndex(uri) orelse return;
        const doc = self.documents.orderedRemove(idx);
        self.allocator.free(doc.uri);
        self.allocator.free(doc.source);
    }

    pub fn findDocument(self: *const ServerState, uri: []const u8) ?*const Document {
        const idx = self.findDocumentIndex(uri) orelse return null;
        return &self.documents.items[idx];
    }

    fn findDocumentIndex(self: *const ServerState, uri: []const u8) ?usize {
        for (self.documents.items, 0..) |doc, idx| {
            if (std.mem.eql(u8, doc.uri, uri)) return idx;
        }
        return null;
    }

    fn replaceSource(self: *ServerState, idx: usize, text: []const u8) !void {
        const owned_source = try self.allocator.dupe(u8, text);
        self.allocator.free(self.documents.items[idx].source);
        self.documents.items[idx].source = owned_source;
    }
};

pub fn run(init: std.process.Init, args: []const []const u8) !void {
    const allocator = init.gpa;
    const io = init.io;

    const parsed = cli.parseLsp(args) catch |err| {
        try diag.printCliError(io, err);
        std.process.exit(1);
    };
    _ = parsed;

    const dep_root = try env.resolveDepRoot(allocator, init.environ_map);
    defer dep_root.deinit(allocator);

    var state = ServerState.init(allocator, dep_root.path);
    defer state.deinit();

    var in_buffer: [4096]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().reader(io, &in_buffer);

    var out_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &out_buffer);
    try serve(io, allocator, &state, &stdin_reader.interface, &stdout_writer.interface);
    try stdout_writer.interface.flush();
}

fn serve(
    io: std.Io,
    allocator: std.mem.Allocator,
    state: *ServerState,
    reader: *std.Io.Reader,
    writer: anytype,
) !void {
    while (true) {
        const body = readFrame(allocator, reader) catch |err| switch (err) {
            error.EndOfStream => return,
            else => return err,
        };
        defer allocator.free(body);

        handleMessage(io, allocator, state, writer, body) catch |err| switch (err) {
            error.LspExit => return,
            else => return err,
        };
    }
}

fn readFrame(allocator: std.mem.Allocator, reader: *std.Io.Reader) ![]u8 {
    var content_length: ?usize = null;
    while (true) {
        const line = try reader.takeDelimiterInclusive('\n');
        if (std.mem.eql(u8, line, "\r\n") or std.mem.eql(u8, line, "\n")) break;

        const trimmed = std.mem.trimEnd(u8, line, "\r\n");
        if (std.mem.startsWith(u8, trimmed, "Content-Length:")) {
            const raw_len = std.mem.trim(u8, trimmed["Content-Length:".len..], " \t");
            const parsed_len = try std.fmt.parseInt(usize, raw_len, 10);
            if (parsed_len > max_frame_len) return error.StreamTooLong;
            content_length = parsed_len;
        }
    }

    const len = content_length orelse return error.MissingContentLength;
    const body = try allocator.alloc(u8, len);
    errdefer allocator.free(body);
    try reader.readSliceAll(body);
    return body;
}

fn handleMessage(
    io: std.Io,
    allocator: std.mem.Allocator,
    state: *ServerState,
    writer: anytype,
    body: []const u8,
) !void {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
    defer parsed.deinit();

    const root = parsed.value;
    const method = jsonStringField(root, "method") orelse return;
    const id = jsonRequestId(root);

    if (std.mem.eql(u8, method, "initialize")) {
        try protocol.writeInitializeResponse(allocator, writer, id);
        return;
    }
    if (std.mem.eql(u8, method, "initialized")) return;
    if (std.mem.eql(u8, method, "textDocument/didOpen")) {
        const uri = jsonPathString(root, &.{ "params", "textDocument", "uri" }) orelse return;
        const text = jsonPathString(root, &.{ "params", "textDocument", "text" }) orelse return;
        try state.didOpen(uri, text);
        try publishDiagnostics(io, allocator, state, writer, uri, text);
        return;
    }
    if (std.mem.eql(u8, method, "textDocument/didChange")) {
        const uri = jsonPathString(root, &.{ "params", "textDocument", "uri" }) orelse return;
        const text = jsonPathString(root, &.{ "params", "contentChanges", "0", "text" }) orelse return;
        try state.didChange(uri, text);
        try publishDiagnostics(io, allocator, state, writer, uri, text);
        return;
    }
    if (std.mem.eql(u8, method, "textDocument/didClose")) {
        const uri = jsonPathString(root, &.{ "params", "textDocument", "uri" }) orelse return;
        try state.didClose(uri);
        try protocol.writePublishDiagnostics(allocator, writer, uri, &.{});
        return;
    }
    if (std.mem.eql(u8, method, "textDocument/formatting")) {
        const uri = jsonPathString(root, &.{ "params", "textDocument", "uri" }) orelse return;
        const doc = state.findDocument(uri) orelse return;
        const formatted = try formatter.formatSource(allocator, doc.source);
        defer allocator.free(formatted);
        const edit = protocol.TextEdit{
            .range = fullDocumentRange(doc.source),
            .new_text = formatted,
        };
        try protocol.writeTextEditsResponse(allocator, writer, id, &.{edit});
        return;
    }
    if (std.mem.eql(u8, method, "textDocument/semanticTokens/full")) {
        const uri = jsonPathString(root, &.{ "params", "textDocument", "uri" }) orelse return;
        const doc = state.findDocument(uri) orelse return;
        const tokens = try semantic_tokens.collectSemanticTokens(allocator, doc.source);
        defer allocator.free(tokens);
        const data = try semantic_tokens.encodeSemanticTokens(allocator, tokens);
        defer allocator.free(data);
        try protocol.writeSemanticTokensResponse(allocator, writer, id, data);
        return;
    }
    if (std.mem.eql(u8, method, "shutdown")) {
        state.shutdown_requested = true;
        try protocol.writeShutdownResponse(allocator, writer, id);
        return;
    }
    if (std.mem.eql(u8, method, "exit")) return error.LspExit;

    if (id != .null) try writeMethodNotFound(allocator, writer, id, method);
}

fn publishDiagnostics(
    io: std.Io,
    allocator: std.mem.Allocator,
    state: *ServerState,
    writer: anytype,
    uri: []const u8,
    text: []const u8,
) !void {
    const collected = try diagnostics.collectDiagnostics(io, allocator, uri, text, state.dep_root);
    defer allocator.free(collected);
    try protocol.writePublishDiagnostics(allocator, writer, uri, collected);
}

fn writeMethodNotFound(
    allocator: std.mem.Allocator,
    writer: anytype,
    id: protocol.RequestId,
    method: []const u8,
) !void {
    var body = std.Io.Writer.Allocating.init(allocator);
    defer body.deinit();

    const body_writer = &body.writer;
    try body_writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
    try writeRequestId(body_writer, id);
    try body_writer.writeAll(",\"error\":{\"code\":-32601,\"message\":\"Method not found\",\"data\":");
    try std.json.Stringify.value(method, .{}, body_writer);
    try body_writer.writeAll("}}");

    try writer.print("Content-Length: {d}\r\n\r\n", .{body_writer.buffered().len});
    try writer.writeAll(body_writer.buffered());
}

fn writeRequestId(writer: anytype, id: protocol.RequestId) !void {
    switch (id) {
        .number => |value| try writer.print("{d}", .{value}),
        .string => |value| try std.json.Stringify.value(value, .{}, writer),
        .null => try writer.writeAll("null"),
    }
}

fn jsonRequestId(root: std.json.Value) protocol.RequestId {
    if (root != .object) return .null;
    const value = root.object.get("id") orelse return .null;
    return switch (value) {
        .integer => |i| .{ .number = i },
        .string => |s| .{ .string = s },
        else => .null,
    };
}

fn jsonStringField(root: std.json.Value, field: []const u8) ?[]const u8 {
    if (root != .object) return null;
    const value = root.object.get(field) orelse return null;
    return switch (value) {
        .string => |s| s,
        else => null,
    };
}

fn jsonPathString(root: std.json.Value, path: []const []const u8) ?[]const u8 {
    const value = jsonPath(root, path) orelse return null;
    return switch (value) {
        .string => |s| s,
        else => null,
    };
}

fn jsonPath(root: std.json.Value, path: []const []const u8) ?std.json.Value {
    var current = root;
    for (path) |part| {
        current = switch (current) {
            .object => |object| object.get(part) orelse return null,
            .array => |array| blk: {
                const idx = std.fmt.parseInt(usize, part, 10) catch return null;
                if (idx >= array.items.len) return null;
                break :blk array.items[idx];
            },
            else => return null,
        };
    }
    return current;
}

fn fullDocumentRange(source: []const u8) protocol.Range {
    if (source.len == 0) {
        return .{
            .start = .{ .line = 0, .character = 0 },
            .end = .{ .line = 0, .character = 0 },
        };
    }

    var line: usize = 0;
    var line_start: usize = 0;
    var last_line_len: usize = 0;

    for (source, 0..) |ch, idx| {
        if (ch == '\n') {
            last_line_len = idx - line_start;
            line += 1;
            line_start = idx + 1;
        }
    }

    if (source[source.len - 1] != '\n') {
        last_line_len = source.len - line_start;
    } else {
        last_line_len = 0;
    }

    return .{
        .start = .{ .line = 0, .character = 0 },
        .end = .{
            .line = line,
            .character = last_line_len,
        },
    };
}

test "fullDocumentRange handles empty and trailing newline sources" {
    const empty = fullDocumentRange("");
    try std.testing.expectEqual(@as(usize, 0), empty.end.line);
    try std.testing.expectEqual(@as(usize, 0), empty.end.character);

    const without_trailing_newline = fullDocumentRange("User {\n    id i32\n}");
    try std.testing.expectEqual(@as(usize, 2), without_trailing_newline.end.line);
    try std.testing.expectEqual(@as(usize, 1), without_trailing_newline.end.character);

    const with_trailing_newline = fullDocumentRange("User {\n    id i32\n}\n");
    try std.testing.expectEqual(@as(usize, 3), with_trailing_newline.end.line);
    try std.testing.expectEqual(@as(usize, 0), with_trailing_newline.end.character);
}

test "ServerState stores and updates open documents" {
    var state = ServerState.init(std.testing.allocator, "tool/build/test/lib");
    defer state.deinit();

    try state.didOpen("file:///tmp/app.do", "test \"bad\" {");
    try std.testing.expectEqual(@as(usize, 1), state.documents.items.len);

    try state.didChange("file:///tmp/app.do",
        \\test "ok" {
        \\    return
        \\}
        \\
    );
    const doc = state.findDocument("file:///tmp/app.do").?;
    try std.testing.expect(std.mem.indexOf(u8, doc.source, "return") != null);
}

test "handleMessage opens document and publishes diagnostics" {
    var state = ServerState.init(std.testing.allocator, "tool/build/test/lib");
    defer state.deinit();

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    try handleMessage(
        std.testing.io,
        std.testing.allocator,
        &state,
        &out.writer,
        "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///tmp/app.do\",\"text\":\"test \\\"bad\"}}}",
    );

    try std.testing.expect(state.findDocument("file:///tmp/app.do") != null);
    const bytes = out.writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"method\":\"textDocument/publishDiagnostics\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"diagnostics\":[") != null);
}

test "handleMessage changes document and clears diagnostics" {
    var state = ServerState.init(std.testing.allocator, "tool/build/test/lib");
    defer state.deinit();

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    try state.didOpen("file:///tmp/app.do", "test \"bad");
    try handleMessage(
        std.testing.io,
        std.testing.allocator,
        &state,
        &out.writer,
        "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didChange\",\"params\":{\"textDocument\":{\"uri\":\"file:///tmp/app.do\"},\"contentChanges\":[{\"text\":\"test \\\"ok\\\" {\\n    return\\n}\\n\"}]}}",
    );

    const doc = state.findDocument("file:///tmp/app.do").?;
    try std.testing.expect(std.mem.indexOf(u8, doc.source, "return") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.writer.buffered(), "\"diagnostics\":[]") != null);
}

test "handleMessage formats open document" {
    var state = ServerState.init(std.testing.allocator, "tool/build/test/lib");
    defer state.deinit();

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    try state.didOpen("file:///tmp/app.do", "User {\nid i32\n}");
    try handleMessage(
        std.testing.io,
        std.testing.allocator,
        &state,
        &out.writer,
        "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/formatting\",\"id\":2,\"params\":{\"textDocument\":{\"uri\":\"file:///tmp/app.do\",\"version\":1},\"options\":{\"tabSize\":4,\"insertSpaces\":true}}}",
    );

    const bytes = out.writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"result\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"newText\":\"User {\\n    id i32\\n}\\n\"") != null);
}
