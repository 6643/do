const std = @import("std");

pub fn format_source(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, source.len + 1);
    defer out.deinit(allocator);

    var indent: usize = 0;
    var i: usize = 0;
    while (i < source.len) {
        const line_start = i;
        while (i < source.len and source[i] != '\n' and source[i] != '\r') : (i += 1) {}
        const raw_line = source[line_start..i];
        const line = trim_right(raw_line);
        const body = trim_left(line);

        if (body.len == 0) {
            try out.append(allocator, '\n');
        } else {
            const line_indent = if (starts_with_closing_brace(body) and indent > 0) indent - 1 else indent;
            try write_indent(&out, allocator, line_indent);
            try out.appendSlice(allocator, body);
            try out.append(allocator, '\n');

            indent = next_indent(indent, body);
        }

        if (i < source.len and source[i] == '\r') {
            i += 1;
            if (i < source.len and source[i] == '\n') i += 1;
        } else if (i < source.len and source[i] == '\n') {
            i += 1;
        }
    }

    while (out.items.len > 1 and out.items[out.items.len - 1] == '\n' and out.items[out.items.len - 2] == '\n') {
        _ = out.pop();
    }
    if (out.items.len == 0 or out.items[out.items.len - 1] != '\n') {
        try out.append(allocator, '\n');
    }

    return out.toOwnedSlice(allocator);
}

fn write_indent(out: *std.ArrayList(u8), allocator: std.mem.Allocator, level: usize) !void {
    var i: usize = 0;
    while (i < level) : (i += 1) {
        try out.appendSlice(allocator, "    ");
    }
}

fn next_indent(current: usize, body: []const u8) usize {
    var indent = current;
    var i: usize = 0;
    while (i < body.len) : (i += 1) {
        switch (body[i]) {
            '{' => indent += 1,
            '}' => if (indent > 0) {
                indent -= 1;
            },
            else => {},
        }
    }
    return indent;
}

fn starts_with_closing_brace(line: []const u8) bool {
    return line.len != 0 and line[0] == '}';
}

fn trim_left(line: []const u8) []const u8 {
    var start: usize = 0;
    while (start < line.len and (line[start] == ' ' or line[start] == '\t')) : (start += 1) {}
    return line[start..];
}

fn trim_right(line: []const u8) []const u8 {
    var end = line.len;
    while (end > 0 and (line[end - 1] == ' ' or line[end - 1] == '\t')) : (end -= 1) {}
    return line[0..end];
}

test "format_source normalizes braces indentation and final newline" {
    const input =
        \\User {
        \\id i32
        \\name text
        \\}
    ;
    const expected =
        \\User {
        \\    id i32
        \\    name text
        \\}
        \\
    ;
    const actual = try format_source(std.testing.allocator, input);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings(expected, actual);
}

test "format_source preserves line string payload" {
    const input =
        \\make() -> text {
        \\return
        \\    \\hello
        \\}
    ;
    const expected =
        \\make() -> text {
        \\    return
        \\    \\hello
        \\}
        \\
    ;
    const actual = try format_source(std.testing.allocator, input);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings(expected, actual);
}

test "format_source normalizes CRLF trailing whitespace and is idempotent" {
    const input = "User {\r\n\tid i32   \r\n}\r\n\r\n";
    const expected =
        \\User {
        \\    id i32
        \\}
        \\
    ;

    const actual = try format_source(std.testing.allocator, input);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings(expected, actual);

    const again = try format_source(std.testing.allocator, actual);
    defer std.testing.allocator.free(again);
    try std.testing.expectEqualStrings(actual, again);
}
