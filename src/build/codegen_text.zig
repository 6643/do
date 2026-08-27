const std = @import("std");

/// Append a single generated-text line or fragment using named standard-format
/// arguments. Multiline structured text must use append_block or
/// append_fmt_block so its indentation is explicit.
pub fn append_fmt(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    comptime format: []const u8,
    args: anytype,
) !void {
    validate_named_format_args(@TypeOf(args));
    const rendered = try std.fmt.allocPrint(allocator, format, args);
    defer allocator.free(rendered);
    try out.appendSlice(allocator, rendered);
}

/// Allocate a single generated-text line or fragment using named
/// standard-format arguments. Multiline structured text must use alloc_block
/// or alloc_fmt_block so its indentation is explicit.
pub fn alloc_fmt(
    allocator: std.mem.Allocator,
    comptime format: []const u8,
    args: anytype,
) ![]u8 {
    validate_named_format_args(@TypeOf(args));
    return std.fmt.allocPrint(allocator, format, args);
}

/// Append a structured multiline text block after normalizing incidental
/// common indentation. Only ASCII spaces participate in indentation.
pub fn append_block(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    base_indent: usize,
    template: []const u8,
) !void {
    const common_indent = find_common_indent(template);
    var line_start: usize = 0;

    while (true) {
        const line_end = find_line_end(template, line_start);
        const line = template[line_start..line_end];
        if (!is_blank_line(line)) {
            const leading = leading_ascii_spaces(line);
            const remove = @min(common_indent, leading);
            try append_spaces(allocator, out, base_indent);
            try out.appendSlice(allocator, line[remove..]);
        }

        if (line_end == template.len) break;
        try out.append(allocator, '\n');
        line_start = line_end + 1;
    }
}

/// Format a structured multiline text block with named standard-format
/// arguments, then apply the same indentation normalization as append_block.
pub fn append_fmt_block(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    base_indent: usize,
    comptime format: []const u8,
    args: anytype,
) !void {
    validate_named_format_args(@TypeOf(args));
    const rendered = try std.fmt.allocPrint(allocator, format, args);
    defer allocator.free(rendered);
    try append_block(allocator, out, base_indent, rendered);
}

/// Allocate a normalized structured block for APIs that return owned bytes.
pub fn alloc_block(
    allocator: std.mem.Allocator,
    base_indent: usize,
    template: []const u8,
) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try append_block(allocator, &out, base_indent, template);
    return out.toOwnedSlice(allocator);
}

/// Allocate a formatted normalized structured block for APIs that return owned bytes.
pub fn alloc_fmt_block(
    allocator: std.mem.Allocator,
    base_indent: usize,
    comptime format: []const u8,
    args: anytype,
) ![]u8 {
    validate_named_format_args(@TypeOf(args));
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try append_fmt_block(allocator, &out, base_indent, format, args);
    return out.toOwnedSlice(allocator);
}

fn find_line_end(text: []const u8, start: usize) usize {
    var index = start;
    while (index < text.len and text[index] != '\n') : (index += 1) {}
    return index;
}

fn leading_ascii_spaces(line: []const u8) usize {
    var count: usize = 0;
    while (count < line.len and line[count] == ' ') : (count += 1) {}
    return count;
}

fn is_blank_line(line: []const u8) bool {
    for (line) |byte| {
        if (byte != ' ') return false;
    }
    return true;
}

fn find_common_indent(text: []const u8) usize {
    var minimum: ?usize = null;
    var line_start: usize = 0;

    while (true) {
        const line_end = find_line_end(text, line_start);
        const line = text[line_start..line_end];
        if (!is_blank_line(line)) {
            const leading = leading_ascii_spaces(line);
            minimum = if (minimum) |current| @min(current, leading) else leading;
        }

        if (line_end == text.len) break;
        line_start = line_end + 1;
    }

    return minimum orelse 0;
}

fn append_spaces(allocator: std.mem.Allocator, out: *std.ArrayList(u8), count: usize) !void {
    var index: usize = 0;
    while (index < count) : (index += 1) {
        try out.append(allocator, ' ');
    }
}

fn is_named_format_args(comptime Args: type) bool {
    return switch (@typeInfo(Args)) {
        .@"struct" => |info| !info.is_tuple or info.fields.len == 0,
        else => false,
    };
}

fn validate_named_format_args(comptime Args: type) void {
    if (comptime !is_named_format_args(Args)) {
        @compileError("generated-text format arguments must use named fields");
    }
}

test "text block removes common indentation and preserves relative indentation" {
    const allocator = std.testing.allocator;
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    try append_block(allocator, &out, 2, "\n          one\n            two\n          three\n");

    try std.testing.expectEqualStrings("\n  one\n    two\n  three\n", out.items);
}

test "text block preserves blank lines and treats tabs as content" {
    const allocator = std.testing.allocator;
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    try append_block(allocator, &out, 1, "  first\n\n  \tsecond\n");

    try std.testing.expectEqualStrings(" first\n\n \tsecond\n", out.items);
}

test "formatted text block accepts named arguments" {
    const allocator = std.testing.allocator;
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    try append_fmt_block(allocator, &out, 0, "    local.get ${[name]s}\n    i32.const {[offset]d}\n", .{ .name = "value", .offset = 4 });

    try std.testing.expectEqualStrings("local.get $value\ni32.const 4\n", out.items);
}

test "single-line format helpers preserve exact bytes and named arguments" {
    const allocator = std.testing.allocator;
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    try append_fmt(allocator, &out, "    local.get ${[name]s}\n", .{ .name = "value" });
    const constant = try alloc_fmt(allocator, "i32.const {[value]d}", .{ .value = 4 });
    defer allocator.free(constant);

    try std.testing.expectEqualStrings("    local.get $value\n", out.items);
    try std.testing.expectEqualStrings("i32.const 4", constant);
}

test "format helpers distinguish named fields from positional arguments" {
    try std.testing.expect(is_named_format_args(@TypeOf(.{ .name = "value" })));
    try std.testing.expect(!is_named_format_args(@TypeOf(.{"value"})));
    try std.testing.expect(is_named_format_args(@TypeOf(.{})));
}

test "empty text block emits no bytes" {
    const allocator = std.testing.allocator;
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    try append_block(allocator, &out, 3, "");
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
}
