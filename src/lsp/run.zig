const std = @import("std");
const cli = @import("../build/cli.zig");
const completion = @import("completion.zig");
const definition = @import("definition.zig");
const diag = @import("../build/diag.zig");
const diagnostics = @import("../build/diagnostics.zig");
const env = @import("../env.zig");
const formatter = @import("../fmt/format.zig");
const hover = @import("hover.zig");
const protocol = @import("protocol.zig");
const semantic_tokens = @import("semantic_tokens.zig");
const workspace = @import("workspace.zig");

const max_frame_len = 16 * 1024 * 1024;

pub const Document = struct {
    uri: []const u8,
    source: []const u8,
};

pub const ServerState = struct {
    allocator: std.mem.Allocator,
    dep_root: []const u8,
    documents: std.ArrayList(Document),
    workspace_roots: std.ArrayList([]const u8),
    workspace_symbols: std.ArrayList(workspace.WorkspaceSymbol),
    shutdown_requested: bool = false,

    pub fn init(allocator: std.mem.Allocator, dep_root: []const u8) ServerState {
        return .{
            .allocator = allocator,
            .dep_root = dep_root,
            .documents = .empty,
            .workspace_roots = .empty,
            .workspace_symbols = .empty,
        };
    }

    pub fn deinit(self: *ServerState) void {
        for (self.documents.items) |doc| {
            self.allocator.free(doc.uri);
            self.allocator.free(doc.source);
        }
        self.documents.deinit(self.allocator);
        self.clear_workspace_roots();
        self.workspace_roots.deinit(self.allocator);
        self.clear_workspace_symbols();
        self.* = .init(self.allocator, self.dep_root);
    }

    pub fn add_workspace_root(self: *ServerState, uri: []const u8) !void {
        const owned_uri = try self.allocator.dupe(u8, uri);
        errdefer self.allocator.free(owned_uri);
        try self.workspace_roots.append(self.allocator, owned_uri);
    }

    pub fn clear_workspace_roots(self: *ServerState) void {
        for (self.workspace_roots.items) |uri| {
            self.allocator.free(uri);
        }
        self.workspace_roots.clearRetainingCapacity();
    }

    pub fn refresh_workspace_symbols(self: *ServerState, io: std.Io) !void {
        const symbols = try workspace.collect_workspace_symbols(io, self.allocator, self.workspace_roots.items);
        self.clear_workspace_symbols();
        self.workspace_symbols = std.ArrayList(workspace.WorkspaceSymbol).fromOwnedSlice(symbols);
    }

    fn clear_workspace_symbols(self: *ServerState) void {
        workspace.free_workspace_symbol_list(self.allocator, &self.workspace_symbols);
        self.workspace_symbols = .empty;
    }

    pub fn did_open(self: *ServerState, uri: []const u8, text: []const u8) !void {
        if (self.find_document_index(uri)) |idx| {
            try self.replace_source(idx, text);
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

    pub fn did_change(self: *ServerState, uri: []const u8, text: []const u8) !void {
        const idx = self.find_document_index(uri) orelse {
            try self.did_open(uri, text);
            return;
        };
        try self.replace_source(idx, text);
    }

    pub fn did_close(self: *ServerState, uri: []const u8) !void {
        const idx = self.find_document_index(uri) orelse return;
        const doc = self.documents.orderedRemove(idx);
        self.allocator.free(doc.uri);
        self.allocator.free(doc.source);
    }

    pub fn find_document(self: *const ServerState, uri: []const u8) ?*const Document {
        const idx = self.find_document_index(uri) orelse return null;
        return &self.documents.items[idx];
    }

    fn find_document_index(self: *const ServerState, uri: []const u8) ?usize {
        for (self.documents.items, 0..) |doc, idx| {
            if (std.mem.eql(u8, doc.uri, uri)) return idx;
        }
        return null;
    }

    fn replace_source(self: *ServerState, idx: usize, text: []const u8) !void {
        const owned_source = try self.allocator.dupe(u8, text);
        self.allocator.free(self.documents.items[idx].source);
        self.documents.items[idx].source = owned_source;
    }
};

pub fn run(init: std.process.Init, args: []const []const u8) !void {
    const allocator = init.gpa;
    const io = init.io;

    const parsed = cli.parse_lsp(args) catch |err| {
        try diag.print_cli_error(io, err);
        std.process.exit(1);
    };
    _ = parsed;

    const dep_root = try env.resolve_dep_root(allocator, init.environ_map);
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
        const body = read_frame(allocator, reader) catch |err| switch (err) {
            error.EndOfStream => return,
            else => return err,
        };
        defer allocator.free(body);

        handle_message(io, allocator, state, writer, body) catch |err| switch (err) {
            error.LspExit => return,
            else => return err,
        };
    }
}

fn read_frame(allocator: std.mem.Allocator, reader: *std.Io.Reader) ![]u8 {
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

fn handle_message(
    io: std.Io,
    allocator: std.mem.Allocator,
    state: *ServerState,
    writer: anytype,
    body: []const u8,
) !void {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
    defer parsed.deinit();

    const root = parsed.value;
    const method = json_string_field(root, "method") orelse return;
    const id = json_request_id(root);

    if (std.mem.eql(u8, method, "initialize")) {
        try record_initialize_workspace_roots(state, root);
        try state.refresh_workspace_symbols(io);
        try protocol.write_initialize_response(allocator, writer, id);
        return;
    }
    if (std.mem.eql(u8, method, "initialized")) return;
    if (std.mem.eql(u8, method, "textDocument/didOpen")) {
        const uri = json_path_string(root, &.{ "params", "textDocument", "uri" }) orelse return;
        const text = json_path_string(root, &.{ "params", "textDocument", "text" }) orelse return;
        try state.did_open(uri, text);
        try publish_diagnostics(io, allocator, state, writer, uri, text);
        return;
    }
    if (std.mem.eql(u8, method, "textDocument/didChange")) {
        const uri = json_path_string(root, &.{ "params", "textDocument", "uri" }) orelse return;
        const text = json_path_string(root, &.{ "params", "contentChanges", "0", "text" }) orelse return;
        try state.did_change(uri, text);
        try publish_diagnostics(io, allocator, state, writer, uri, text);
        return;
    }
    if (std.mem.eql(u8, method, "textDocument/didClose")) {
        const uri = json_path_string(root, &.{ "params", "textDocument", "uri" }) orelse return;
        try state.did_close(uri);
        try protocol.write_publish_diagnostics(allocator, writer, uri, &.{});
        return;
    }
    if (std.mem.eql(u8, method, "textDocument/formatting")) {
        const uri = json_path_string(root, &.{ "params", "textDocument", "uri" }) orelse return;
        const doc = state.find_document(uri) orelse return;
        const formatted = try formatter.format_source(allocator, doc.source);
        defer allocator.free(formatted);
        const edit = protocol.TextEdit{
            .range = full_document_range(doc.source),
            .new_text = formatted,
        };
        try protocol.write_text_edits_response(allocator, writer, id, &.{edit});
        return;
    }
    if (std.mem.eql(u8, method, "textDocument/semanticTokens/full")) {
        const uri = json_path_string(root, &.{ "params", "textDocument", "uri" }) orelse return;
        const doc = state.find_document(uri) orelse return;
        const tokens = try semantic_tokens.collect_semantic_tokens(allocator, doc.source);
        defer allocator.free(tokens);
        const data = try semantic_tokens.encode_semantic_tokens(allocator, tokens);
        defer allocator.free(data);
        try protocol.write_semantic_tokens_response(allocator, writer, id, data);
        return;
    }
    if (std.mem.eql(u8, method, "textDocument/hover")) {
        const uri = json_path_string(root, &.{ "params", "textDocument", "uri" }) orelse return;
        const line = json_path_unsigned(root, &.{ "params", "position", "line" }) orelse return;
        const character = json_path_unsigned(root, &.{ "params", "position", "character" }) orelse return;
        const doc = state.find_document(uri) orelse {
            try protocol.write_hover_response(allocator, writer, id, null);
            return;
        };
        const contents = try hover.find_hover(allocator, doc.source, .{
            .line = line,
            .character = character,
        });
        defer if (contents) |value| allocator.free(value);
        try protocol.write_hover_response(allocator, writer, id, contents);
        return;
    }
    if (std.mem.eql(u8, method, "textDocument/completion")) {
        const uri = json_path_string(root, &.{ "params", "textDocument", "uri" }) orelse return;
        const line = json_path_unsigned(root, &.{ "params", "position", "line" }) orelse return;
        const character = json_path_unsigned(root, &.{ "params", "position", "character" }) orelse return;
        const doc = state.find_document(uri) orelse {
            try protocol.write_completion_response(allocator, writer, id, &.{});
            return;
        };
        const items = try completion.collect_completion_items_with_workspace(allocator, doc.source, .{
            .line = line,
            .character = character,
        }, state.workspace_symbols.items);
        defer allocator.free(items);
        try protocol.write_completion_response(allocator, writer, id, items);
        return;
    }
    if (std.mem.eql(u8, method, "textDocument/definition")) {
        const uri = json_path_string(root, &.{ "params", "textDocument", "uri" }) orelse return;
        const line = json_path_unsigned(root, &.{ "params", "position", "line" }) orelse return;
        const character = json_path_unsigned(root, &.{ "params", "position", "character" }) orelse return;
        const doc = state.find_document(uri) orelse {
            try protocol.write_definition_response(allocator, writer, id, null);
            return;
        };
        const location = try definition.find_definition_with_workspace(allocator, uri, doc.source, .{
            .line = line,
            .character = character,
        }, state.workspace_symbols.items);
        try protocol.write_definition_response(allocator, writer, id, location);
        return;
    }
    if (std.mem.eql(u8, method, "shutdown")) {
        state.shutdown_requested = true;
        try protocol.write_shutdown_response(allocator, writer, id);
        return;
    }
    if (std.mem.eql(u8, method, "exit")) return error.LspExit;

    if (id != .null) try write_method_not_found(allocator, writer, id, method);
}

fn publish_diagnostics(
    io: std.Io,
    allocator: std.mem.Allocator,
    state: *ServerState,
    writer: anytype,
    uri: []const u8,
    text: []const u8,
) !void {
    const collected = try diagnostics.collect_diagnostics(io, allocator, uri, text, state.dep_root);
    defer allocator.free(collected);
    try protocol.write_publish_diagnostics(allocator, writer, uri, collected);
}

fn record_initialize_workspace_roots(state: *ServerState, root: std.json.Value) !void {
    state.clear_workspace_roots();
    errdefer state.clear_workspace_roots();

    if (json_path(root, &.{ "params", "workspaceFolders" })) |folders_value| {
        switch (folders_value) {
            .array => |folders| {
                for (folders.items) |folder| {
                    const uri = json_path_string(folder, &.{"uri"}) orelse continue;
                    try state.add_workspace_root(uri);
                }
                if (state.workspace_roots.items.len != 0) return;
            },
            else => {},
        }
    }

    const root_uri = json_path_string(root, &.{ "params", "rootUri" }) orelse return;
    try state.add_workspace_root(root_uri);
}

fn write_method_not_found(
    allocator: std.mem.Allocator,
    writer: anytype,
    id: protocol.RequestId,
    method: []const u8,
) !void {
    var body = std.Io.Writer.Allocating.init(allocator);
    defer body.deinit();

    const body_writer = &body.writer;
    try body_writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
    try write_request_id(body_writer, id);
    try body_writer.writeAll(",\"error\":{\"code\":-32601,\"message\":\"Method not found\",\"data\":");
    try std.json.Stringify.value(method, .{}, body_writer);
    try body_writer.writeAll("}}");

    try writer.print("Content-Length: {d}\r\n\r\n", .{body_writer.buffered().len});
    try writer.writeAll(body_writer.buffered());
}

fn write_request_id(writer: anytype, id: protocol.RequestId) !void {
    switch (id) {
        .number => |value| try writer.print("{d}", .{value}),
        .string => |value| try std.json.Stringify.value(value, .{}, writer),
        .null => try writer.writeAll("null"),
    }
}

fn json_request_id(root: std.json.Value) protocol.RequestId {
    if (root != .object) return .null;
    const value = root.object.get("id") orelse return .null;
    return switch (value) {
        .integer => |i| .{ .number = i },
        .string => |s| .{ .string = s },
        else => .null,
    };
}

fn json_string_field(root: std.json.Value, field: []const u8) ?[]const u8 {
    if (root != .object) return null;
    const value = root.object.get(field) orelse return null;
    return switch (value) {
        .string => |s| s,
        else => null,
    };
}

fn json_path_string(root: std.json.Value, path: []const []const u8) ?[]const u8 {
    const value = json_path(root, path) orelse return null;
    return switch (value) {
        .string => |s| s,
        else => null,
    };
}

fn json_path_unsigned(root: std.json.Value, path: []const []const u8) ?usize {
    const value = json_path(root, path) orelse return null;
    return switch (value) {
        .integer => |i| if (i < 0) null else @as(usize, @intCast(i)),
        else => null,
    };
}

fn json_path(root: std.json.Value, path: []const []const u8) ?std.json.Value {
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

fn full_document_range(source: []const u8) protocol.Range {
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

test "full_document_range handles empty and trailing newline sources" {
    const empty = full_document_range("");
    try std.testing.expectEqual(@as(usize, 0), empty.end.line);
    try std.testing.expectEqual(@as(usize, 0), empty.end.character);

    const without_trailing_newline = full_document_range("User {\n    id i32\n}");
    try std.testing.expectEqual(@as(usize, 2), without_trailing_newline.end.line);
    try std.testing.expectEqual(@as(usize, 1), without_trailing_newline.end.character);

    const with_trailing_newline = full_document_range("User {\n    id i32\n}\n");
    try std.testing.expectEqual(@as(usize, 3), with_trailing_newline.end.line);
    try std.testing.expectEqual(@as(usize, 0), with_trailing_newline.end.character);
}

test "ServerState stores and updates open documents" {
    var state = ServerState.init(std.testing.allocator, "src/build/test/lib");
    defer state.deinit();

    try state.did_open("file:///tmp/app.do", "test \"bad\" {");
    try std.testing.expectEqual(@as(usize, 1), state.documents.items.len);

    try state.did_change("file:///tmp/app.do",
        \\test "ok" {
        \\    return
        \\}
        \\
    );
    const doc = state.find_document("file:///tmp/app.do").?;
    try std.testing.expect(std.mem.indexOf(u8, doc.source, "return") != null);
}

test "handle_message records initialize workspace folders" {
    var state = ServerState.init(std.testing.allocator, "src/build/test/lib");
    defer state.deinit();

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    try handle_message(
        std.testing.io,
        std.testing.allocator,
        &state,
        &out.writer,
        "{\"jsonrpc\":\"2.0\",\"method\":\"initialize\",\"id\":1,\"params\":{\"workspaceFolders\":[{\"uri\":\"file:///tmp/do-one\",\"name\":\"one\"},{\"uri\":\"file:///tmp/do-two\",\"name\":\"two\"}],\"rootUri\":\"file:///tmp/fallback\"}}",
    );

    try std.testing.expectEqual(@as(usize, 2), state.workspace_roots.items.len);
    try std.testing.expectEqualStrings("file:///tmp/do-one", state.workspace_roots.items[0]);
    try std.testing.expectEqualStrings("file:///tmp/do-two", state.workspace_roots.items[1]);
    try std.testing.expect(std.mem.indexOf(u8, out.writer.buffered(), "\"capabilities\"") != null);
}

test "handle_message records rootUri when workspace folders are absent" {
    var state = ServerState.init(std.testing.allocator, "src/build/test/lib");
    defer state.deinit();

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    try handle_message(
        std.testing.io,
        std.testing.allocator,
        &state,
        &out.writer,
        "{\"jsonrpc\":\"2.0\",\"method\":\"initialize\",\"id\":1,\"params\":{\"rootUri\":\"file:///tmp/do-root\",\"capabilities\":{}}}",
    );

    try std.testing.expectEqual(@as(usize, 1), state.workspace_roots.items.len);
    try std.testing.expectEqualStrings("file:///tmp/do-root", state.workspace_roots.items[0]);
}

test "handle_message indexes workspace symbols from initialize roots" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "user.do",
        .data =
        \\User {
        \\    title text
        \\}
        \\
        \\get_title(user User) -> text {
        \\    return @get(user, .title)
        \\}
        \\
        ,
    });

    const root_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root_path);
    const root_uri = try std.fmt.allocPrint(std.testing.allocator, "file://{s}", .{root_path});
    defer std.testing.allocator.free(root_uri);
    const initialize = try std.fmt.allocPrint(
        std.testing.allocator,
        "{{\"jsonrpc\":\"2.0\",\"method\":\"initialize\",\"id\":1,\"params\":{{\"rootUri\":\"{s}\",\"capabilities\":{{}}}}}}",
        .{root_uri},
    );
    defer std.testing.allocator.free(initialize);

    var state = ServerState.init(std.testing.allocator, "src/build/test/lib");
    defer state.deinit();

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    try handle_message(std.testing.io, std.testing.allocator, &state, &out.writer, initialize);

    try expect_workspace_symbol(state.workspace_symbols.items, "User", .type_name);
    try expect_workspace_symbol(state.workspace_symbols.items, "get_title", .function);
}

test "handle_message opens document and publishes diagnostics" {
    var state = ServerState.init(std.testing.allocator, "src/build/test/lib");
    defer state.deinit();

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    try handle_message(
        std.testing.io,
        std.testing.allocator,
        &state,
        &out.writer,
        "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///tmp/app.do\",\"text\":\"test \\\"bad\"}}}",
    );

    try std.testing.expect(state.find_document("file:///tmp/app.do") != null);
    const bytes = out.writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"method\":\"textDocument/publishDiagnostics\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"diagnostics\":[") != null);
}

test "handle_message changes document and clears diagnostics" {
    var state = ServerState.init(std.testing.allocator, "src/build/test/lib");
    defer state.deinit();

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    try state.did_open("file:///tmp/app.do", "test \"bad");
    try handle_message(
        std.testing.io,
        std.testing.allocator,
        &state,
        &out.writer,
        "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didChange\",\"params\":{\"textDocument\":{\"uri\":\"file:///tmp/app.do\"},\"contentChanges\":[{\"text\":\"test \\\"ok\\\" {\\n    return\\n}\\n\"}]}}",
    );

    const doc = state.find_document("file:///tmp/app.do").?;
    try std.testing.expect(std.mem.indexOf(u8, doc.source, "return") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.writer.buffered(), "\"diagnostics\":[]") != null);
}

test "handle_message formats open document" {
    var state = ServerState.init(std.testing.allocator, "src/build/test/lib");
    defer state.deinit();

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    try state.did_open("file:///tmp/app.do", "User {\nid i32\n}");
    try handle_message(
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

test "handle_message returns hover for open document function name" {
    var state = ServerState.init(std.testing.allocator, "src/build/test/lib");
    defer state.deinit();

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    try state.did_open("file:///tmp/app.do",
        \\User {
        \\    title text
        \\}
        \\get_title(user User) -> text {
        \\    return @get(user, .title)
        \\}
        \\
    );
    try handle_message(
        std.testing.io,
        std.testing.allocator,
        &state,
        &out.writer,
        "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/hover\",\"id\":2,\"params\":{\"textDocument\":{\"uri\":\"file:///tmp/app.do\"},\"position\":{\"line\":3,\"character\":3}}}",
    );

    const bytes = out.writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"kind\":\"plaintext\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"value\":\"get_title(user User) -> text\"") != null);
}

test "handle_message returns completion items for open document" {
    var state = ServerState.init(std.testing.allocator, "src/build/test/lib");
    defer state.deinit();

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    try state.did_open("file:///tmp/app.do",
        \\User {
        \\    title text
        \\}
        \\
        \\get_title(user User) -> text {
        \\    return @get(user, .)
        \\}
        \\
    );
    try handle_message(
        std.testing.io,
        std.testing.allocator,
        &state,
        &out.writer,
        "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/completion\",\"id\":2,\"params\":{\"textDocument\":{\"uri\":\"file:///tmp/app.do\"},\"position\":{\"line\":5,\"character\":23}}}",
    );

    const bytes = out.writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"result\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "{\"label\":\"User\",\"kind\":7") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "{\"label\":\"get_title\",\"kind\":3") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "{\"label\":\"title\",\"kind\":5") != null);
}

test "handle_message returns definition for open document function call" {
    var state = ServerState.init(std.testing.allocator, "src/build/test/lib");
    defer state.deinit();

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    try state.did_open("file:///tmp/app.do",
        \\User {
        \\    title text
        \\}
        \\
        \\get_title(user User) -> text {
        \\    return @get(user, .title)
        \\}
        \\
        \\test "call" {
        \\    value text = get_title(User{ title = "a" })
        \\    return
        \\}
        \\
    );
    try handle_message(
        std.testing.io,
        std.testing.allocator,
        &state,
        &out.writer,
        "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/definition\",\"id\":2,\"params\":{\"textDocument\":{\"uri\":\"file:///tmp/app.do\"},\"position\":{\"line\":9,\"character\":18}}}",
    );

    const bytes = out.writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"result\":{\"uri\":\"file:///tmp/app.do\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"start\":{\"line\":4,\"character\":0}") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"end\":{\"line\":4,\"character\":9}") != null);
}

fn expect_workspace_symbol(
    symbols: []const workspace.WorkspaceSymbol,
    name: []const u8,
    kind: workspace.WorkspaceSymbolKind,
) !void {
    for (symbols) |symbol| {
        if (!std.mem.eql(u8, symbol.name, name)) continue;
        try std.testing.expectEqual(kind, symbol.kind);
        return;
    }
    return error.MissingWorkspaceSymbol;
}
