const std = @import("std");

pub const SlotSpec = struct {
    slot_size: u32,
    slot_count: u32,
    header_size: u32,
    utilization: u32,
};

pub fn findOptimalSpec(raw_size: u32) SlotSpec {
    const page_size: u32 = 4096;
    const fixed_header_base: u32 = 8;
    const slot_size = (raw_size + 3) & ~@as(u32, 3);
    const n = (8 * (page_size - fixed_header_base)) / (8 * slot_size + 1);
    const bitmap_bytes = (n + 7) / 8;
    const header_size = (fixed_header_base + bitmap_bytes + 7) & ~@as(u32, 7);
    
    return SlotSpec {
        .slot_size = slot_size,
        .slot_count = n,
        .header_size = header_size,
        .utilization = (n * slot_size * 100) / page_size,
    };
}

pub fn printHeader(rc_bytes: u8, id_bytes: u8) void {
    std.debug.print("\n[Compile] Global Meta: RC({d}B) + TypeID({d}B) = {d}B (Native 64-bit Aligned)\n", .{
        rc_bytes, id_bytes, rc_bytes + id_bytes 
    });
    std.debug.print("--------------------------------------------------------------------------------\n", .{});
}

pub fn printReport(id: u32, type_name: []const u8, raw_size: u32, rc_bytes: u8, id_bytes: u8) void {
    const spec = findOptimalSpec(raw_size);
    std.debug.print("[Compile] ID: {d:<2} | Type: {s:<10} | Meta: RC({d}B)+ID({d}B) | Raw: {d:>3}B | Slot: {d:>3}B | N: {d:>3} | Util: {d:>2}%\n", .{
        id, type_name, rc_bytes, id_bytes, raw_size, spec.slot_size, spec.slot_count, spec.utilization,
    });
}