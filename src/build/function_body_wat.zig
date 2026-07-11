const std = @import("std");

pub fn emitFuncOpen(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    name: []const u8,
) !void {
    try appendFmt(allocator, out, "  (func ${s}\n", .{name});
}

pub fn emitFuncClose(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
) !void {
    try out.appendSlice(allocator, "  )\n");
}

pub fn emitFuncExport(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    export_name: []const u8,
    func_name: []const u8,
) !void {
    try appendFmt(allocator, out, "  (export \"{s}\" (func ${s}))\n", .{ export_name, func_name });
}

pub fn emitLocalDecl(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    name: []const u8,
    ty: []const u8,
) !void {
    try appendFmt(allocator, out, "    (local ${s} {s})\n", .{ name, ty });
}

pub fn emitCompiledTestOpen(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    index: usize,
    name_lexeme: []const u8,
) !void {
    try appendFmt(allocator, out, "  ;; compiled-test {d} {s}\n", .{ index, name_lexeme });
    try appendFmt(allocator, out, "  (func $__test_{d}\n", .{index});
}

pub fn emitCompiledTestExport(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    index: usize,
) !void {
    try appendFmt(allocator, out, "  (export \"__test_{d}\" (func $__test_{d}))\n", .{ index, index });
}

pub fn emitTestStartFunc(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    test_count: usize,
) !void {
    try out.appendSlice(allocator, "  (func $_start\n");
    for (0..test_count) |idx| {
        try appendFmt(allocator, out, "    call $__test_{d}\n", .{idx});
    }
    try out.appendSlice(allocator, "  )\n");
    try out.appendSlice(allocator, "  (export \"_start\" (func $_start))\n");
}

fn appendFmt(
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

    try emitFuncOpen(allocator, &out, "_start");
    try emitLocalDecl(allocator, &out, "x", "i32");
    try emitFuncClose(allocator, &out);
    try emitFuncExport(allocator, &out, "_start", "_start");

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

    try emitCompiledTestOpen(allocator, &out, 2, "\"adds\"");
    try emitFuncClose(allocator, &out);
    try emitCompiledTestExport(allocator, &out, 2);
    try emitTestStartFunc(allocator, &out, 3);

    try std.testing.expect(std.mem.indexOf(u8, out.items, "  ;; compiled-test 2 \"adds\"\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "  (export \"__test_2\" (func $__test_2))\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "    call $__test_0\n    call $__test_1\n    call $__test_2\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "  (export \"_start\" (func $_start))\n") != null);
}
