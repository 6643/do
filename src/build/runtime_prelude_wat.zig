const std = @import("std");
const runtime_arc_wat = @import("runtime_arc_wat.zig");

pub const ManagedFieldOffset = runtime_arc_wat.ManagedFieldOffset;
pub const StructLayout = runtime_arc_wat.StructLayout;
pub const StringData = runtime_arc_wat.StringData;

pub const MemoryOptions = struct {
    component_core: bool = false,
};

pub const ARC_BLOCK_SIZE = runtime_arc_wat.ARC_BLOCK_SIZE;
pub const ARC_OBJECT_HEADER_BYTES = runtime_arc_wat.ARC_OBJECT_HEADER_BYTES;
pub const ARC_RELEASE_WORKLIST_BYTES = runtime_arc_wat.ARC_RELEASE_WORKLIST_BYTES;
pub const WASI_RESULT_AREA_BYTES = runtime_arc_wat.WASI_RESULT_AREA_BYTES;


// Re-export ARC runtime WAT (physical home: runtime_arc_wat.zig).
pub const alignUp = runtime_arc_wat.alignUp;
pub const alignedArcHeapBase = runtime_arc_wat.alignedArcHeapBase;
pub const appendFmt = runtime_arc_wat.appendFmt;
pub const emitArcLayoutTable = runtime_arc_wat.emitArcLayoutTable;
pub const emitArcRuntimeHeader = runtime_arc_wat.emitArcRuntimeHeader;
pub const emitArcRuntimePrelude = runtime_arc_wat.emitArcRuntimePrelude;
pub const hasEarlierLayoutTypeId = runtime_arc_wat.hasEarlierLayoutTypeId;

pub fn emitStringDataMemory(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    string_data: []const StringData,
    options: MemoryOptions,
) !void {
    if (options.component_core) {
        try out.appendSlice(allocator, "  (memory 1)\n");
    } else {
        try out.appendSlice(allocator, "  (memory (export \"memory\") 1)\n");
    }
    try out.appendSlice(allocator, "  (export \"cm32p2_memory\" (memory 0))\n");
    for (string_data) |data| {
        try appendFmt(allocator, out, "  (data (i32.const {d}) ", .{data.ptr});
        try appendWatStringLiteral(allocator, out, data.bytes);
        try out.appendSlice(allocator, ")\n");
    }
}

fn appendWatStringLiteral(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    bytes: []const u8,
) !void {
    try out.append(allocator, '"');
    for (bytes) |byte| {
        if (byte >= 0x20 and byte <= 0x7e and byte != '"' and byte != '\\') {
            try out.append(allocator, byte);
            continue;
        }
        try appendWatByteEscape(allocator, out, byte);
    }
    try out.append(allocator, '"');
}

fn appendWatByteEscape(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    byte: u8,
) !void {
    const digits = "0123456789abcdef";
    try out.append(allocator, '\\');
    try out.append(allocator, digits[byte >> 4]);
    try out.append(allocator, digits[byte & 0x0f]);
}

test "runtime prelude writer emits component core memory and data segments" {
    const allocator = std.testing.allocator;
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    const data = [_]StringData{
        .{ .ptr = 1024, .bytes = "a\nb" },
    };
    try emitStringDataMemory(allocator, &out, data[0..], .{ .component_core = true });

    try std.testing.expect(std.mem.indexOf(u8, out.items, "  (memory 1)\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "  (export \"cm32p2_memory\" (memory 0))\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "  (data (i32.const 1024) \"a\\0ab\")\n") != null);
}

test "runtime prelude writer emits runtime header and layout table" {
    const allocator = std.testing.allocator;
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    const fields = [_]ManagedFieldOffset{
        .{ .name = "items", .offset = 12 },
    };
    const layouts = [_]StructLayout{
        .{ .name = "Box", .type_id = 2, .payload_bytes = 16, .managed_fields = fields[0..] },
    };
    try emitArcRuntimeHeader(allocator, &out, &.{}, layouts[0..]);
    try emitArcLayoutTable(allocator, &out, layouts[0..]);

    try std.testing.expect(std.mem.indexOf(u8, out.items, "  ;; arc-runtime block_size=1024 object_header=8\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "  (global $__heap_base i32 (i32.const 2048))\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "  ;; arc-layout type_id=2 name=Box managed_count=1 payload_bytes=16\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "  ;; arc-layout-managed-offset type_id=2 index=0 offset=12 field=items\n") != null);
}
