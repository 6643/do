const std = @import("std");

pub fn emit_func_open(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    name: []const u8,
) !void {
    try append_fmt(allocator, out, "  (func ${s}\n", .{name});
}

pub fn emit_func_close(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
) !void {
    try out.appendSlice(allocator, "  )\n");
}

pub fn emit_func_export(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    export_name: []const u8,
    func_name: []const u8,
) !void {
    try append_fmt(allocator, out, "  (export \"{s}\" (func ${s}))\n", .{ export_name, func_name });
}

pub fn emit_local_decl(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    name: []const u8,
    ty: []const u8,
) !void {
    try append_fmt(allocator, out, "    (local ${s} {s})\n", .{ name, ty });
}

pub fn emit_compiled_test_open(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    index: usize,
    name_lexeme: []const u8,
) !void {
    try append_fmt(allocator, out, "  ;; compiled-test {d} {s}\n", .{ index, name_lexeme });
    try append_fmt(allocator, out, "  (func $__test_{d}\n", .{index});
}

pub fn emit_compiled_test_export(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    index: usize,
) !void {
    try append_fmt(allocator, out, "  (export \"__test_{d}\" (func $__test_{d}))\n", .{ index, index });
}

pub fn emit_test_start_func(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    test_count: usize,
) !void {
    try out.appendSlice(allocator, "  (func $_start\n");
    for (0..test_count) |idx| {
        try append_fmt(allocator, out, "    call $__test_{d}\n", .{idx});
    }
    try out.appendSlice(allocator, "  )\n");
    try out.appendSlice(allocator, "  (export \"_start\" (func $_start))\n");
}

fn append_fmt(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    comptime fmt: []const u8,
    args: anytype,
) !void {
    const text = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(text);
    try out.appendSlice(allocator, text);
}

test "function body writer emits function shell locals and export" {
    const allocator = std.testing.allocator;
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    try emit_func_open(allocator, &out, "_start");
    try emit_local_decl(allocator, &out, "x", "i32");
    try emit_func_close(allocator, &out);
    try emit_func_export(allocator, &out, "_start", "_start");

    try std.testing.expectEqualStrings(
        \\  (func $_start
        \\    (local $x i32)
        \\  )
        \\  (export "_start" (func $_start))
        \\
    , out.items);
}

test "function body writer emits compiled test manifest and start calls" {
    const allocator = std.testing.allocator;
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    try emit_compiled_test_open(allocator, &out, 2, "\"adds\"");
    try emit_func_close(allocator, &out);
    try emit_compiled_test_export(allocator, &out, 2);
    try emit_test_start_func(allocator, &out, 3);

    try std.testing.expect(std.mem.indexOf(u8, out.items, "  ;; compiled-test 2 \"adds\"\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "  (export \"__test_2\" (func $__test_2))\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "    call $__test_0\n    call $__test_1\n    call $__test_2\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "  (export \"_start\" (func $_start))\n") != null);
}
