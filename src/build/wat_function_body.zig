const std = @import("std");
const generated_text = @import("codegen_text.zig");

pub fn emit_func_open(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    name: []const u8,
) !void {
    try generated_text.append_fmt(allocator, out, "  (func ${[name]s}\n", .{ .name = name });
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
    try generated_text.append_fmt(allocator, out, "  (export \"{[export_name]s}\" (func ${[func_name]s}))\n", .{ .export_name = export_name, .func_name = func_name });
}

pub fn emit_local_decl(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    name: []const u8,
    ty: []const u8,
) !void {
    try generated_text.append_fmt(allocator, out, "    (local ${[name]s} {[ty]s})\n", .{ .name = name, .ty = ty });
}

pub fn emit_compiled_test_open(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    index: usize,
    name_lexeme: []const u8,
) !void {
    try generated_text.append_fmt(allocator, out, "  ;; compiled-test {[index]d} {[name]s}\n", .{ .index = index, .name = name_lexeme });
    try generated_text.append_fmt(allocator, out, "  (func $__test_{[index]d}\n", .{ .index = index });
}

pub fn emit_compiled_test_export(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    index: usize,
) !void {
    try generated_text.append_fmt(allocator, out, "  (export \"__test_{[index]d}\" (func $__test_{[index]d}))\n", .{ .index = index });
}

pub fn emit_test_start_func(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    test_count: usize,
) !void {
    try out.appendSlice(allocator, "  (func $_start\n");
    for (0..test_count) |idx| {
        try generated_text.append_fmt(allocator, out, "    call $__test_{[index]d}\n", .{ .index = idx });
    }
    try out.appendSlice(allocator, "  )\n");
    try out.appendSlice(allocator, "  (export \"_start\" (func $_start))\n");
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
