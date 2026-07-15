//! ARC runtime WAT prelude (extracted from runtime_prelude_wat).
const std = @import("std");

pub const ManagedFieldOffset = struct {
    name: []const u8,
    offset: usize,
};

pub const StructLayout = struct {
    name: []const u8,
    type_id: usize,
    payload_bytes: usize,
    managed_fields: []const ManagedFieldOffset,
    owned_name: bool = false,
    /// When true: this layout describes one packed storage element (payload_bytes = elem width;
    /// managed_fields offsets are relative to element start). Used for `[Tuple<...>]` with managed leaves.
    is_storage_pack: bool = false,
};

pub const StringData = struct {
    lexeme: []const u8 = "",
    ptr: usize,
    bytes: []const u8,
};

pub const ARC_BLOCK_SIZE: usize = 1024;
pub const ARC_OBJECT_HEADER_BYTES: usize = 8;
pub const ARC_RELEASE_WORKLIST_BYTES: usize = 512;
pub const WASI_RESULT_AREA_BYTES: usize = 64;

pub fn emit_arc_runtime_header(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    string_data: []const StringData,
    struct_layouts: []const StructLayout,
) !void {
    _ = struct_layouts;
    const heap_base = aligned_arc_heap_base(string_data);
    const release_worklist_base = heap_base - ARC_RELEASE_WORKLIST_BYTES;
    const wasi_result_area_base = release_worklist_base - WASI_RESULT_AREA_BYTES;

    try append_fmt(allocator, out, "  ;; arc-runtime block_size={d} object_header={d}\n", .{ ARC_BLOCK_SIZE, ARC_OBJECT_HEADER_BYTES });
    try append_fmt(allocator, out, "  (global $__heap_base i32 (i32.const {d}))\n", .{heap_base});
    try append_fmt(allocator, out, "  (global $__heap_cursor (mut i32) (i32.const {d}))\n", .{heap_base});
    try append_fmt(allocator, out, "  (global $__wasi_result_area_base i32 (i32.const {d}))\n", .{wasi_result_area_base});
    try append_fmt(allocator, out, "  (global $__release_worklist_base i32 (i32.const {d}))\n", .{release_worklist_base});
}


pub fn emit_arc_layout_table(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    struct_layouts: []const StructLayout,
) !void {
    for (struct_layouts) |layout| {
        try append_fmt(allocator, out, "  ;; arc-layout type_id={d} name={s} managed_count={d} payload_bytes={d}\n", .{
            layout.type_id,
            layout.name,
            layout.managed_fields.len,
            layout.payload_bytes,
        });
        for (layout.managed_fields, 0..) |field, index| {
            try append_fmt(allocator, out, "  ;; arc-layout-managed-offset type_id={d} index={d} offset={d} field={s}\n", .{
                layout.type_id,
                index,
                field.offset,
                field.name,
            });
        }
    }

    try out.appendSlice(allocator,
        \\  (func $__layout_managed_count (param $type_id i32) (result i32)
        \\    local.get $type_id
        \\    i32.const 1
        \\    i32.eq
        \\    if
        \\      i32.const 0
        \\      return
        \\    end
        \\
    );
    for (struct_layouts, 0..) |layout, index| {
        if (has_earlier_layout_type_id(struct_layouts[0..index], layout.type_id)) continue;
        try append_fmt(allocator, out,
            \\    local.get $type_id
            \\    i32.const {d}
            \\    i32.eq
            \\    if
            \\      i32.const {d}
            \\      return
            \\    end
            \\
        , .{ layout.type_id, layout.managed_fields.len });
    }
    try out.appendSlice(allocator,
        \\    unreachable
        \\  )
        \\  (func $__layout_managed_offset (param $type_id i32) (param $index i32) (result i32)
        \\    local.get $type_id
        \\    i32.const 1
        \\    i32.eq
        \\    if
        \\      unreachable
        \\    end
        \\
    );
    for (struct_layouts, 0..) |layout, index| {
        if (has_earlier_layout_type_id(struct_layouts[0..index], layout.type_id)) continue;
        try append_fmt(allocator, out,
            \\    local.get $type_id
            \\    i32.const {d}
            \\    i32.eq
            \\    if
            \\
        , .{layout.type_id});
        for (layout.managed_fields, 0..) |field, field_index| {
            try append_fmt(allocator, out,
                \\      local.get $index
                \\      i32.const {d}
                \\      i32.eq
                \\      if
                \\        i32.const {d}
                \\        return
                \\      end
                \\
            , .{ field_index, field.offset });
        }
        try out.appendSlice(allocator,
            \\      unreachable
            \\    end
            \\
        );
    }
    try out.appendSlice(allocator,
        \\    unreachable
        \\  )
        \\  (func $__layout_is_storage_pack (param $type_id i32) (result i32)
        \\    local.get $type_id
        \\    i32.const 1
        \\    i32.eq
        \\    if
        \\      i32.const 0
        \\      return
        \\    end
        \\
    );
    for (struct_layouts, 0..) |layout, index| {
        if (has_earlier_layout_type_id(struct_layouts[0..index], layout.type_id)) continue;
        if (!layout.is_storage_pack) continue;
        try append_fmt(allocator, out,
            \\    local.get $type_id
            \\    i32.const {d}
            \\    i32.eq
            \\    if
            \\      i32.const 1
            \\      return
            \\    end
            \\
        , .{layout.type_id});
    }
    try out.appendSlice(allocator,
        \\    i32.const 0
        \\  )
        \\  (func $__layout_storage_pack_elem_bytes (param $type_id i32) (result i32)
        \\    local.get $type_id
        \\    i32.const 1
        \\    i32.eq
        \\    if
        \\      unreachable
        \\    end
        \\
    );
    for (struct_layouts, 0..) |layout, index| {
        if (has_earlier_layout_type_id(struct_layouts[0..index], layout.type_id)) continue;
        if (!layout.is_storage_pack) continue;
        try append_fmt(allocator, out,
            \\    local.get $type_id
            \\    i32.const {d}
            \\    i32.eq
            \\    if
            \\      i32.const {d}
            \\      return
            \\    end
            \\
        , .{ layout.type_id, layout.payload_bytes });
    }
    try out.appendSlice(allocator,
        \\    unreachable
        \\  )
    );
}


pub fn emit_arc_runtime_prelude(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    string_data: []const StringData,
    struct_layouts: []const StructLayout,
) !void {
    try emit_arc_runtime_header(allocator, out, string_data, struct_layouts);
    try out.appendSlice(allocator,
        \\  ;; arc-runtime memory grow helper v0
        \\  (func $__memory_grow_to (param $end i32)
        \\    memory.size
        \\    i32.const 16
        \\    i32.shl
        \\    local.get $end
        \\    i32.lt_u
        \\    if
        \\      local.get $end
        \\      i32.const 65535
        \\      i32.add
        \\      i32.const 16
        \\      i32.shr_u
        \\      memory.size
        \\      i32.sub
        \\      memory.grow
        \\      i32.const -1
        \\      i32.eq
        \\      if
        \\        unreachable
        \\      end
        \\    end
        \\  )
        \\  (func $cm32p2_realloc (export "cm32p2_realloc") (param $old_ptr i32) (param $old_size i32) (param $align i32) (param $new_size i32) (result i32)
        \\    (local $ptr i32)
        \\    (local $copy_len i32)
        \\    local.get $new_size
        \\    i32.eqz
        \\    if
        \\      i32.const 0
        \\      return
        \\    end
        \\    global.get $__heap_cursor
        \\    local.get $align
        \\    i32.const 1
        \\    i32.sub
        \\    i32.add
        \\    local.get $align
        \\    i32.const 1
        \\    i32.sub
        \\    i32.const -1
        \\    i32.xor
        \\    i32.and
        \\    local.set $ptr
        \\    local.get $ptr
        \\    local.get $new_size
        \\    i32.add
        \\    call $__memory_grow_to
        \\    local.get $ptr
        \\    local.get $new_size
        \\    i32.add
        \\    global.set $__heap_cursor
        \\    local.get $old_ptr
        \\    i32.eqz
        \\    i32.eqz
        \\    if
        \\      local.get $old_size
        \\      local.set $copy_len
        \\      local.get $new_size
        \\      local.get $old_size
        \\      i32.lt_u
        \\      if
        \\        local.get $new_size
        \\        local.set $copy_len
        \\      end
        \\      local.get $ptr
        \\      local.get $old_ptr
        \\      local.get $copy_len
        \\      memory.copy
        \\    end
        \\    local.get $ptr
        \\  )
        \\  (func $cm32p2_initialize (export "cm32p2_initialize"))
        \\  (func $__wasi_list_u8_to_storage (param $ptr i32) (param $len i32) (result i32)
        \\    (local $object i32)
        \\    local.get $len
        \\    i32.const 8
        \\    i32.add
        \\    i32.const 1
        \\    call $__arc_alloc
        \\    local.set $object
        \\    local.get $object
        \\    call $__arc_payload
        \\    local.get $len
        \\    i32.store
        \\    local.get $object
        \\    call $__arc_payload
        \\    i32.const 4
        \\    i32.add
        \\    local.get $len
        \\    i32.store
        \\    local.get $object
        \\    call $__arc_payload
        \\    i32.const 8
        \\    i32.add
        \\    local.get $ptr
        \\    local.get $len
        \\    memory.copy
        \\    local.get $object
        \\  )
        \\  ;; G6.1 / P3: host list of (descriptor,string) → [Tuple<Dir,text>] storage pack.
        \\  ;; Element ABI: descriptor@0, string.ptr@4, string.len@8 (12 bytes).
        \\  ;; Pack slot: Dir.id i64 @0 + text handle @8 (12 bytes). type_id is storage-pack layout.
        \\  (func $__wasi_list_preopen_to_storage (param $ptr i32) (param $len i32) (param $type_id i32) (result i32)
        \\    (local $object i32)
        \\    (local $i i32)
        \\    (local $elem i32)
        \\    (local $dst i32)
        \\    (local $path_ptr i32)
        \\    (local $path_len i32)
        \\    (local $path_obj i32)
        \\    (local $fd i32)
        \\    local.get $len
        \\    i32.const 12
        \\    i32.mul
        \\    i32.const 8
        \\    i32.add
        \\    local.get $type_id
        \\    call $__arc_alloc
        \\    local.set $object
        \\    local.get $object
        \\    call $__arc_payload
        \\    local.get $len
        \\    i32.store
        \\    local.get $object
        \\    call $__arc_payload
        \\    i32.const 4
        \\    i32.add
        \\    local.get $len
        \\    i32.store
        \\    i32.const 0
        \\    local.set $i
        \\    block $done
        \\      loop $scan
        \\        local.get $i
        \\        local.get $len
        \\        i32.ge_u
        \\        br_if $done
        \\        local.get $ptr
        \\        local.get $i
        \\        i32.const 12
        \\        i32.mul
        \\        i32.add
        \\        local.set $elem
        \\        local.get $elem
        \\        i32.load
        \\        local.set $fd
        \\        local.get $elem
        \\        i32.const 4
        \\        i32.add
        \\        i32.load
        \\        local.set $path_ptr
        \\        local.get $elem
        \\        i32.const 8
        \\        i32.add
        \\        i32.load
        \\        local.set $path_len
        \\        local.get $path_ptr
        \\        local.get $path_len
        \\        call $__wasi_list_u8_to_storage
        \\        local.set $path_obj
        \\        local.get $object
        \\        call $__arc_payload
        \\        i32.const 8
        \\        i32.add
        \\        local.get $i
        \\        i32.const 12
        \\        i32.mul
        \\        i32.add
        \\        local.set $dst
        \\        local.get $dst
        \\        local.get $fd
        \\        i64.extend_i32_s
        \\        i64.store
        \\        local.get $dst
        \\        i32.const 8
        \\        i32.add
        \\        local.get $path_obj
        \\        i32.store
        \\        local.get $i
        \\        i32.const 1
        \\        i32.add
        \\        local.set $i
        \\        br $scan
        \\      end
        \\    end
        \\    local.get $object
        \\  )
        \\  ;; arc-runtime free span list v1
        \\  (global $__free_span_head (mut i32) (i32.const -1))
        \\  (func $__free_span_push (param $block i32)
        \\    local.get $block
        \\    i32.const 8
        \\    i32.add
        \\    global.get $__free_span_head
        \\    i32.store
        \\    local.get $block
        \\    global.set $__free_span_head
        \\  )
        \\  (func $__free_span_find (param $required_span i32) (result i32)
        \\    (local $block i32)
        \\    global.get $__free_span_head
        \\    local.set $block
        \\    block $not_found
        \\      loop $scan
        \\        local.get $block
        \\        i32.const -1
        \\        i32.eq
        \\        br_if $not_found
        \\        local.get $block
        \\        i32.load8_u
        \\        i32.eqz
        \\        local.get $block
        \\        i32.const 4
        \\        i32.add
        \\        i32.load
        \\        local.get $required_span
        \\        i32.ge_u
        \\        i32.and
        \\        if
        \\          local.get $block
        \\          return
        \\        end
        \\        local.get $block
        \\        i32.const 8
        \\        i32.add
        \\        i32.load
        \\        local.set $block
        \\        br $scan
        \\      end
        \\    end
        \\    i32.const -1
        \\  )
        \\  ;; arc-runtime free span unlink v1
        \\  (func $__free_span_unlink (param $target i32)
        \\    (local $prev i32)
        \\    (local $block i32)
        \\    i32.const -1
        \\    local.set $prev
        \\    global.get $__free_span_head
        \\    local.set $block
        \\    block $done
        \\      loop $scan
        \\        local.get $block
        \\        i32.const -1
        \\        i32.eq
        \\        br_if $done
        \\        local.get $block
        \\        local.get $target
        \\        i32.eq
        \\        if
        \\          local.get $prev
        \\          i32.const -1
        \\          i32.eq
        \\          if
        \\            local.get $block
        \\            i32.const 8
        \\            i32.add
        \\            i32.load
        \\            global.set $__free_span_head
        \\          else
        \\            local.get $prev
        \\            i32.const 8
        \\            i32.add
        \\            local.get $block
        \\            i32.const 8
        \\            i32.add
        \\            i32.load
        \\            i32.store
        \\          end
        \\          return
        \\        end
        \\        local.get $block
        \\        local.set $prev
        \\        local.get $block
        \\        i32.const 8
        \\        i32.add
        \\        i32.load
        \\        local.set $block
        \\        br $scan
        \\      end
        \\    end
        \\  )
        \\  ;; arc-runtime free span split v1
        \\  (func $__free_span_split_tail (param $block i32) (param $used_span i32)
        \\    (local $original_span i32)
        \\    (local $tail_block i32)
        \\    local.get $block
        \\    i32.const 4
        \\    i32.add
        \\    i32.load
        \\    local.set $original_span
        \\    local.get $original_span
        \\    local.get $used_span
        \\    i32.le_u
        \\    if
        \\      return
        \\    end
        \\    local.get $block
        \\    local.get $used_span
        \\    i32.const 1024
        \\    i32.mul
        \\    i32.add
        \\    local.set $tail_block
        \\    local.get $tail_block
        \\    i32.const 0
        \\    i32.store8
        \\    local.get $tail_block
        \\    i32.const 4
        \\    i32.add
        \\    local.get $original_span
        \\    local.get $used_span
        \\    i32.sub
        \\    i32.store
        \\    local.get $tail_block
        \\    i32.const 8
        \\    i32.add
        \\    i32.const 0
        \\    i32.store
        \\    local.get $tail_block
        \\    call $__free_span_push
        \\    local.get $block
        \\    i32.const 4
        \\    i32.add
        \\    local.get $used_span
        \\    i32.store
        \\  )
        \\  ;; arc-runtime free span merge v1
        \\  (func $__free_span_merge_neighbors (param $block i32) (result i32)
        \\    (local $candidate i32)
        \\    (local $block_span i32)
        \\    (local $candidate_span i32)
        \\    (local $block_end i32)
        \\    (local $candidate_end i32)
        \\    block $done
        \\      loop $restart
        \\        local.get $block
        \\        i32.const 4
        \\        i32.add
        \\        i32.load
        \\        local.set $block_span
        \\        local.get $block
        \\        local.get $block_span
        \\        i32.const 1024
        \\        i32.mul
        \\        i32.add
        \\        local.set $block_end
        \\        global.get $__free_span_head
        \\        local.set $candidate
        \\        block $scan_done
        \\          loop $scan
        \\            local.get $candidate
        \\            i32.const -1
        \\            i32.eq
        \\            br_if $scan_done
        \\            local.get $candidate
        \\            local.get $block
        \\            i32.eq
        \\            if
        \\              local.get $candidate
        \\              i32.const 8
        \\              i32.add
        \\              i32.load
        \\              local.set $candidate
        \\              br $scan
        \\            end
        \\            local.get $candidate
        \\            i32.load8_u
        \\            i32.eqz
        \\            if
        \\              local.get $candidate
        \\              i32.const 4
        \\              i32.add
        \\              i32.load
        \\              local.set $candidate_span
        \\              local.get $candidate
        \\              local.get $candidate_span
        \\              i32.const 1024
        \\              i32.mul
        \\              i32.add
        \\              local.set $candidate_end
        \\              local.get $block_end
        \\              local.get $candidate
        \\              i32.eq
        \\              if
        \\                local.get $candidate
        \\                call $__free_span_unlink
        \\                local.get $block
        \\                i32.const 4
        \\                i32.add
        \\                local.get $block_span
        \\                local.get $candidate_span
        \\                i32.add
        \\                i32.store
        \\                br $restart
        \\              end
        \\              local.get $candidate_end
        \\              local.get $block
        \\              i32.eq
        \\              if
        \\                local.get $candidate
        \\                call $__free_span_unlink
        \\                local.get $candidate
        \\                i32.const 4
        \\                i32.add
        \\                local.get $candidate_span
        \\                local.get $block_span
        \\                i32.add
        \\                i32.store
        \\                local.get $block
        \\                i32.const 0
        \\                i32.store8
        \\                local.get $candidate
        \\                local.set $block
        \\                br $restart
        \\              end
        \\            end
        \\            local.get $candidate
        \\            i32.const 8
        \\            i32.add
        \\            i32.load
        \\            local.set $candidate
        \\            br $scan
        \\          end
        \\        end
        \\        br $done
        \\      end
        \\    end
        \\    local.get $block
        \\  )
        \\  ;; arc-runtime generic slot class table v1
        \\  (func $__slot_class_table_addr (param $slot_units i32) (result i32)
        \\    local.get $slot_units
        \\    i32.const 2
        \\    i32.shl
        \\  )
        \\  (func $__slot_class_table_get (param $slot_units i32) (result i32)
        \\    (local $stored i32)
        \\    ;; zero table slot means no block
        \\    local.get $slot_units
        \\    call $__slot_class_table_addr
        \\    i32.load
        \\    local.tee $stored
        \\    i32.eqz
        \\    if (result i32)
        \\      i32.const -1
        \\    else
        \\      local.get $stored
        \\      i32.const 1
        \\      i32.sub
        \\    end
        \\  )
        \\  (func $__slot_class_table_set (param $slot_units i32) (param $head i32)
        \\    local.get $slot_units
        \\    call $__slot_class_table_addr
        \\    local.get $head
        \\    i32.const 1
        \\    i32.add
        \\    i32.store
        \\  )
        \\  ;; arc-runtime slot class state v1
        \\  (global $__slot_class_4 (mut i32) (i32.const -1))
        \\  (func $__slot_class_head_ptr (param $slot_units i32) (result i32)
        \\    local.get $slot_units
        \\    i32.const 4
        \\    i32.eq
        \\    if (result i32)
        \\      global.get $__slot_class_4
        \\    else
        \\      local.get $slot_units
        \\      call $__slot_class_table_get
        \\    end
        \\  )
        \\  (func $__slot_class_set_head (param $slot_units i32) (param $head i32)
        \\    local.get $slot_units
        \\    local.get $head
        \\    call $__slot_class_table_set
        \\    local.get $slot_units
        \\    i32.const 4
        \\    i32.eq
        \\    if
        \\      local.get $head
        \\      global.set $__slot_class_4
        \\    end
        \\  )
        \\  (func $__slot_class_unlink_block (param $slot_units i32) (param $target i32)
        \\    (local $prev i32)
        \\    (local $block i32)
        \\    i32.const -1
        \\    local.set $prev
        \\    local.get $slot_units
        \\    call $__slot_class_head_ptr
        \\    local.set $block
        \\    block $done
        \\      loop $scan
        \\        local.get $block
        \\        i32.const -1
        \\        i32.eq
        \\        br_if $done
        \\        local.get $block
        \\        local.get $target
        \\        i32.eq
        \\        if
        \\          local.get $prev
        \\          i32.const -1
        \\          i32.eq
        \\          if
        \\            local.get $slot_units
        \\            local.get $block
        \\            i32.const 4
        \\            i32.add
        \\            i32.load
        \\            call $__slot_class_set_head
        \\          else
        \\            local.get $prev
        \\            i32.const 4
        \\            i32.add
        \\            local.get $block
        \\            i32.const 4
        \\            i32.add
        \\            i32.load
        \\            i32.store
        \\          end
        \\          return
        \\        end
        \\        local.get $block
        \\        local.set $prev
        \\        local.get $block
        \\        i32.const 4
        \\        i32.add
        \\        i32.load
        \\        local.set $block
        \\        br $scan
        \\      end
        \\    end
        \\  )
        \\  ;; arc-runtime small slot reuse v1
        \\  (func $__small_data_start (param $cap i32) (result i32)
        \\    i32.const 8
        \\    local.get $cap
        \\    i32.const 7
        \\    i32.add
        \\    i32.const 3
        \\    i32.shr_u
        \\    i32.add
        \\    i32.const 3
        \\    i32.add
        \\    i32.const -4
        \\    i32.and
        \\  )
        \\  (func $__small_find_free_slot (param $block i32) (result i32)
        \\    (local $cap i32)
        \\    (local $slot i32)
        \\    (local $byte i32)
        \\    local.get $block
        \\    i32.load8_u
        \\    local.set $cap
        \\    i32.const 0
        \\    local.set $slot
        \\    block $not_found
        \\      loop $scan
        \\        local.get $slot
        \\        local.get $cap
        \\        i32.ge_u
        \\        br_if $not_found
        \\        local.get $block
        \\        i32.const 8
        \\        i32.add
        \\        local.get $slot
        \\        i32.const 3
        \\        i32.shr_u
        \\        i32.add
        \\        i32.load8_u
        \\        local.set $byte
        \\        local.get $byte
        \\        i32.const 1
        \\        local.get $slot
        \\        i32.const 7
        \\        i32.and
        \\        i32.shl
        \\        i32.and
        \\        i32.eqz
        \\        if
        \\          local.get $slot
        \\          return
        \\        end
        \\        local.get $slot
        \\        i32.const 1
        \\        i32.add
        \\        local.set $slot
        \\        br $scan
        \\      end
        \\    end
        \\    i32.const -1
        \\  )
        \\  (func $__small_find_block_with_slot (param $start_block i32) (result i32)
        \\    (local $block i32)
        \\    local.get $start_block
        \\    local.set $block
        \\    block $not_found
        \\      loop $scan
        \\        local.get $block
        \\        i32.const -1
        \\        i32.eq
        \\        br_if $not_found
        \\        local.get $block
        \\        call $__small_find_free_slot
        \\        i32.const -1
        \\        i32.ne
        \\        if
        \\          local.get $block
        \\          return
        \\        end
        \\        local.get $block
        \\        i32.const 4
        \\        i32.add
        \\        i32.load
        \\        local.set $block
        \\        br $scan
        \\      end
        \\    end
        \\    i32.const -1
        \\  )
        \\  (func $__arc_alloc_from_small (param $block i32) (param $type_id i32) (result i32)
        \\    (local $cap i32)
        \\    (local $slot i32)
        \\    (local $slot_size i32)
        \\    (local $bitmap_addr i32)
        \\    (local $mask i32)
        \\    (local $data_start i32)
        \\    (local $object i32)
        \\    local.get $block
        \\    call $__small_find_free_slot
        \\    local.tee $slot
        \\    i32.const -1
        \\    i32.eq
        \\    if
        \\      unreachable
        \\    end
        \\    local.get $block
        \\    i32.load8_u
        \\    local.set $cap
        \\    local.get $block
        \\    i32.const 1
        \\    i32.add
        \\    i32.load8_u
        \\    i32.const 2
        \\    i32.shl
        \\    local.set $slot_size
        \\    local.get $block
        \\    i32.const 8
        \\    i32.add
        \\    local.get $slot
        \\    i32.const 3
        \\    i32.shr_u
        \\    i32.add
        \\    local.set $bitmap_addr
        \\    i32.const 1
        \\    local.get $slot
        \\    i32.const 7
        \\    i32.and
        \\    i32.shl
        \\    local.set $mask
        \\    local.get $bitmap_addr
        \\    local.get $bitmap_addr
        \\    i32.load8_u
        \\    local.get $mask
        \\    i32.or
        \\    i32.store8
        \\    local.get $cap
        \\    call $__small_data_start
        \\    local.set $data_start
        \\    local.get $block
        \\    local.get $data_start
        \\    i32.add
        \\    local.get $slot
        \\    local.get $slot_size
        \\    i32.mul
        \\    i32.add
        \\    local.set $object
        \\    local.get $object
        \\    i32.const 1
        \\    i32.store
        \\    local.get $object
        \\    i32.const 4
        \\    i32.add
        \\    local.get $type_id
        \\    i32.store
        \\    local.get $object
        \\  )
        \\  ;; arc-runtime small slot release v1
        \\  (func $__small_block_for_object (param $object i32) (result i32)
        \\    local.get $object
        \\    i32.const -1024
        \\    i32.and
        \\  )
        \\  (func $__small_slot_for_object (param $object i32) (result i32)
        \\    (local $block i32)
        \\    (local $cap i32)
        \\    (local $data_start i32)
        \\    (local $slot_size i32)
        \\    local.get $object
        \\    call $__small_block_for_object
        \\    local.set $block
        \\    local.get $block
        \\    i32.load8_u
        \\    local.set $cap
        \\    local.get $cap
        \\    call $__small_data_start
        \\    local.set $data_start
        \\    local.get $block
        \\    i32.const 1
        \\    i32.add
        \\    i32.load8_u
        \\    i32.const 2
        \\    i32.shl
        \\    local.set $slot_size
        \\    local.get $object
        \\    local.get $block
        \\    i32.sub
        \\    local.get $data_start
        \\    i32.sub
        \\    local.get $slot_size
        \\    i32.div_u
        \\  )
        \\  (func $__arc_release_small (param $object i32)
        \\    (local $block i32)
        \\    (local $slot i32)
        \\    (local $bitmap_addr i32)
        \\    (local $mask i32)
        \\    local.get $object
        \\    call $__small_block_for_object
        \\    local.tee $block
        \\    i32.load8_u
        \\    i32.const 1
        \\    i32.le_u
        \\    if
        \\      return
        \\    end
        \\    local.get $object
        \\    call $__small_slot_for_object
        \\    local.set $slot
        \\    local.get $block
        \\    i32.const 8
        \\    i32.add
        \\    local.get $slot
        \\    i32.const 3
        \\    i32.shr_u
        \\    i32.add
        \\    local.set $bitmap_addr
        \\    i32.const 1
        \\    local.get $slot
        \\    i32.const 7
        \\    i32.and
        \\    i32.shl
        \\    i32.const -1
        \\    i32.xor
        \\    local.set $mask
        \\    local.get $bitmap_addr
        \\    local.get $bitmap_addr
        \\    i32.load8_u
        \\    local.get $mask
        \\    i32.and
        \\    i32.store8
        \\    local.get $block
        \\    call $__small_is_empty
        \\    if
        \\      local.get $block
        \\      call $__reclaim_empty_small_block
        \\    end
        \\  )
        \\  ;; arc-runtime empty small block reclaim v1
        \\  (func $__small_is_empty (param $block i32) (result i32)
        \\    (local $cap i32)
        \\    (local $bitmap_bytes i32)
        \\    (local $byte_index i32)
        \\    local.get $block
        \\    i32.load8_u
        \\    local.set $cap
        \\    local.get $cap
        \\    i32.const 7
        \\    i32.add
        \\    i32.const 3
        \\    i32.shr_u
        \\    local.set $bitmap_bytes
        \\    i32.const 0
        \\    local.set $byte_index
        \\    block $empty
        \\      loop $scan
        \\        local.get $byte_index
        \\        local.get $bitmap_bytes
        \\        i32.ge_u
        \\        br_if $empty
        \\        local.get $block
        \\        i32.const 8
        \\        i32.add
        \\        local.get $byte_index
        \\        i32.add
        \\        i32.load8_u
        \\        i32.eqz
        \\        if
        \\        else
        \\          i32.const 0
        \\          return
        \\        end
        \\        local.get $byte_index
        \\        i32.const 1
        \\        i32.add
        \\        local.set $byte_index
        \\        br $scan
        \\      end
        \\    end
        \\    i32.const 1
        \\  )
        \\  (func $__reclaim_empty_small_block (param $block i32)
        \\    (local $slot_units i32)
        \\    local.get $block
        \\    i32.const 1
        \\    i32.add
        \\    i32.load8_u
        \\    local.set $slot_units
        \\    local.get $slot_units
        \\    local.get $block
        \\    call $__slot_class_unlink_block
        \\    local.get $block
        \\    i32.const 0
        \\    i32.store8
        \\    local.get $block
        \\    i32.const 4
        \\    i32.add
        \\    i32.const 1
        \\    i32.store
        \\    local.get $block
        \\    i32.const 8
        \\    i32.add
        \\    i32.const 0
        \\    i32.store
        \\    local.get $block
        \\    call $__free_span_merge_neighbors
        \\    call $__free_span_push
        \\  )
        \\  ;; arc-runtime layout table v1
        \\
    );
    try emit_arc_layout_table(allocator, out, struct_layouts);
    try out.appendSlice(allocator,
        \\  ;; arc-runtime large span release v1
        \\  (func $__arc_release_large (param $object i32)
        \\    (local $block i32)
        \\    (local $span_len i32)
        \\    local.get $object
        \\    call $__small_block_for_object
        \\    local.set $block
        \\    local.get $block
        \\    i32.const 4
        \\    i32.add
        \\    i32.load
        \\    local.set $span_len
        \\    local.get $block
        \\    i32.const 0
        \\    i32.store8
        \\    local.get $block
        \\    i32.const 4
        \\    i32.add
        \\    local.get $span_len
        \\    i32.store
        \\    local.get $block
        \\    i32.const 8
        \\    i32.add
        \\    i32.const 0
        \\    i32.store
        \\    local.get $block
        \\    call $__free_span_merge_neighbors
        \\    call $__free_span_push
        \\  )
        \\  ;; arc-runtime allocator v1
        \\  (func $__arc_alloc (param $payload_bytes i32) (param $type_id i32) (result i32)
        \\    (local $object_bytes i32)
        \\    local.get $payload_bytes
        \\    i32.const 8
        \\    i32.add
        \\    i32.const 3
        \\    i32.add
        \\    i32.const -4
        \\    i32.and
        \\    local.set $object_bytes
        \\    local.get $object_bytes
        \\    i32.const 1024
        \\    i32.lt_u
        \\    if (result i32)
        \\      local.get $payload_bytes
        \\      local.get $type_id
        \\      call $__arc_alloc_small
        \\    else
        \\      local.get $payload_bytes
        \\      local.get $type_id
        \\      call $__arc_alloc_large
        \\    end
        \\  )
        \\  ;; arc-runtime small block allocator v1
        \\  (func $__arc_alloc_small (param $payload_bytes i32) (param $type_id i32) (result i32)
        \\    (local $object_bytes i32)
        \\    (local $slot_units i32)
        \\    (local $cap i32)
        \\    (local $block i32)
        \\    (local $class_head i32)
        \\    (local $reuse_block i32)
        \\    (local $data_start i32)
        \\    local.get $payload_bytes
        \\    i32.const 8
        \\    i32.add
        \\    i32.const 3
        \\    i32.add
        \\    i32.const -4
        \\    i32.and
        \\    local.set $object_bytes
        \\    local.get $object_bytes
        \\    i32.const 2
        \\    i32.add
        \\    i32.const 2
        \\    i32.shr_u
        \\    local.set $slot_units
        \\    i32.const 1024
        \\    local.get $object_bytes
        \\    i32.div_u
        \\    local.set $cap
        \\    local.get $cap
        \\    i32.const 504
        \\    i32.gt_u
        \\    if
        \\      i32.const 504
        \\      local.set $cap
        \\    end
        \\    block $cap_done
        \\      loop $cap_scan
        \\        local.get $cap
        \\        i32.const 1
        \\        i32.le_u
        \\        br_if $cap_done
        \\        local.get $cap
        \\        call $__small_data_start
        \\        local.get $cap
        \\        local.get $object_bytes
        \\        i32.mul
        \\        i32.add
        \\        i32.const 1024
        \\        i32.le_u
        \\        br_if $cap_done
        \\        local.get $cap
        \\        i32.const 1
        \\        i32.sub
        \\        local.set $cap
        \\        br $cap_scan
        \\      end
        \\    end
        \\    local.get $cap
        \\    i32.const 1
        \\    i32.le_u
        \\    if (result i32)
        \\      local.get $payload_bytes
        \\      local.get $type_id
        \\      call $__arc_alloc_large
        \\    else
        \\      global.get $__heap_cursor
        \\      local.set $block
        \\      local.get $slot_units
        \\      call $__slot_class_head_ptr
        \\      local.set $class_head
        \\      local.get $class_head
        \\      call $__small_find_block_with_slot
        \\      local.tee $reuse_block
        \\      i32.const -1
        \\      i32.ne
        \\      if
        \\        local.get $reuse_block
        \\        local.get $type_id
        \\        call $__arc_alloc_from_small
        \\        return
        \\      end
        \\      local.get $block
        \\      i32.const 1024
        \\      i32.add
        \\      call $__memory_grow_to
        \\      local.get $block
        \\      local.get $cap
        \\      i32.store8
        \\      local.get $block
        \\      i32.const 1
        \\      i32.add
        \\      local.get $slot_units
        \\      i32.store8
        \\      local.get $block
        \\      i32.const 2
        \\      i32.add
        \\      i32.const 0
        \\      i32.store8
        \\      local.get $block
        \\      i32.const 3
        \\      i32.add
        \\      i32.const 0
        \\      i32.store8
        \\      local.get $block
        \\      i32.const 4
        \\      i32.add
        \\      local.get $class_head
        \\      i32.store
        \\      local.get $block
        \\      i32.const 8
        \\      i32.add
        \\      i32.const 0
        \\      i32.store8
        \\      local.get $cap
        \\      call $__small_data_start
        \\      local.set $data_start
        \\      local.get $block
        \\      i32.const 1024
        \\      i32.add
        \\      global.set $__heap_cursor
        \\      local.get $slot_units
        \\      local.get $block
        \\      call $__slot_class_set_head
        \\      local.get $block
        \\      local.get $type_id
        \\      call $__arc_alloc_from_small
        \\    end
        \\  )
        \\  ;; arc-runtime large block allocator v1
        \\  (func $__arc_alloc_large (param $payload_bytes i32) (param $type_id i32) (result i32)
        \\    (local $object_bytes i32)
        \\    (local $span_len i32)
        \\    (local $block i32)
        \\    (local $free_block i32)
        \\    (local $object i32)
        \\    local.get $payload_bytes
        \\    i32.const 8
        \\    i32.add
        \\    i32.const 3
        \\    i32.add
        \\    i32.const -4
        \\    i32.and
        \\    local.set $object_bytes
        \\    local.get $object_bytes
        \\    i32.const 8
        \\    i32.add
        \\    i32.const 1023
        \\    i32.add
        \\    i32.const 1024
        \\    i32.div_u
        \\    local.set $span_len
        \\    local.get $span_len
        \\    call $__free_span_find
        \\    local.tee $free_block
        \\    i32.const -1
        \\    i32.ne
        \\    if
        \\      local.get $free_block
        \\      call $__free_span_unlink
        \\      local.get $free_block
        \\      local.get $span_len
        \\      call $__free_span_split_tail
        \\      local.get $free_block
        \\      local.get $payload_bytes
        \\      local.get $type_id
        \\      call $__arc_alloc_from_large_block
        \\      return
        \\    end
        \\    global.get $__heap_cursor
        \\    local.set $block
        \\    local.get $block
        \\    local.get $span_len
        \\    i32.const 1024
        \\    i32.mul
        \\    i32.add
        \\    call $__memory_grow_to
        \\    local.get $block
        \\    i32.const 1
        \\    i32.store8
        \\    local.get $block
        \\    i32.const 4
        \\    i32.add
        \\    local.get $span_len
        \\    i32.store
        \\    local.get $block
        \\    i32.const 8
        \\    i32.add
        \\    local.set $object
        \\    local.get $block
        \\    local.get $span_len
        \\    i32.const 1024
        \\    i32.mul
        \\    i32.add
        \\    global.set $__heap_cursor
        \\    local.get $object
        \\    i32.const 1
        \\    i32.store
        \\    local.get $object
        \\    i32.const 4
        \\    i32.add
        \\    local.get $type_id
        \\    i32.store
        \\    local.get $object
        \\  )
        \\  (func $__arc_alloc_from_large_block (param $block i32) (param $payload_bytes i32) (param $type_id i32) (result i32)
        \\    (local $object i32)
        \\    local.get $block
        \\    i32.const 1
        \\    i32.store8
        \\    local.get $block
        \\    i32.const 8
        \\    i32.add
        \\    local.set $object
        \\    local.get $object
        \\    i32.const 1
        \\    i32.store
        \\    local.get $object
        \\    i32.const 4
        \\    i32.add
        \\    local.get $type_id
        \\    i32.store
        \\    local.get $object
        \\  )
        \\  ;; arc-runtime bump allocator fallback v0
        \\  (func $__arc_alloc_bump (param $payload_bytes i32) (param $type_id i32) (result i32)
        \\    (local $object i32)
        \\    (local $next i32)
        \\    global.get $__heap_cursor
        \\    local.set $object
        \\    local.get $object
        \\    i32.const 8
        \\    i32.add
        \\    local.get $payload_bytes
        \\    i32.const 3
        \\    i32.add
        \\    i32.const -4
        \\    i32.and
        \\    i32.add
        \\    local.set $next
        \\    local.get $next
        \\    call $__memory_grow_to
        \\    local.get $object
        \\    i32.const 1
        \\    i32.store
        \\    local.get $object
        \\    i32.const 4
        \\    i32.add
        \\    local.get $type_id
        \\    i32.store
        \\    local.get $next
        \\    global.set $__heap_cursor
        \\    local.get $object
        \\  )
        \\  ;; arc-runtime release worklist v1
        \\  (global $__release_worklist_top (mut i32) (i32.const 0))
        \\  (func $__release_worklist_push (param $object i32)
        \\    global.get $__release_worklist_top
        \\    i32.const 128
        \\    i32.ge_u
        \\    if
        \\      unreachable
        \\    end
        \\    global.get $__release_worklist_base
        \\    global.get $__release_worklist_top
        \\    i32.const 2
        \\    i32.shl
        \\    i32.add
        \\    local.get $object
        \\    i32.store
        \\    global.get $__release_worklist_top
        \\    i32.const 1
        \\    i32.add
        \\    global.set $__release_worklist_top
        \\  )
        \\  (func $__release_worklist_pop (result i32)
        \\    global.get $__release_worklist_top
        \\    i32.eqz
        \\    if (result i32)
        \\      i32.const 0
        \\    else
        \\      global.get $__release_worklist_top
        \\      i32.const 1
        \\      i32.sub
        \\      global.set $__release_worklist_top
        \\      global.get $__release_worklist_base
        \\      global.get $__release_worklist_top
        \\      i32.const 2
        \\      i32.shl
        \\      i32.add
        \\      i32.load
        \\    end
        \\  )
        \\  ;; arc-storage-managed-release
        \\  (func $__arc_release_storage_managed_children (param $object i32)
        \\    (local $count i32)
        \\    (local $index i32)
        \\    (local $child i32)
        \\    local.get $object
        \\    call $__arc_payload
        \\    i32.load
        \\    local.set $count
        \\    i32.const 0
        \\    local.set $index
        \\    block $done
        \\      loop $scan
        \\        local.get $index
        \\        local.get $count
        \\        i32.ge_u
        \\        br_if $done
        \\        local.get $object
        \\        call $__arc_payload
        \\        i32.const 8
        \\        i32.add
        \\        local.get $index
        \\        i32.const 4
        \\        i32.mul
        \\        i32.add
        \\        i32.load
        \\        local.tee $child
        \\        i32.eqz
        \\        if
        \\        else
        \\          local.get $child
        \\          call $__arc_dec_no_drain
        \\        end
        \\        local.get $index
        \\        i32.const 1
        \\        i32.add
        \\        local.set $index
        \\        br $scan
        \\      end
        \\    end
        \\  )
        \\  ;; arc-storage-pack-managed-release: type_id layout has is_storage_pack;
        \\  ;; payload_bytes = elem width; managed offsets relative to each element.
        \\  (func $__arc_release_storage_pack_children (param $object i32) (param $type_id i32)
        \\    (local $count i32)
        \\    (local $elem_i i32)
        \\    (local $leaf_i i32)
        \\    (local $leaf_n i32)
        \\    (local $elem_bytes i32)
        \\    (local $base i32)
        \\    (local $child i32)
        \\    local.get $object
        \\    call $__arc_payload
        \\    i32.load
        \\    local.set $count
        \\    local.get $type_id
        \\    call $__layout_storage_pack_elem_bytes
        \\    local.set $elem_bytes
        \\    local.get $type_id
        \\    call $__layout_managed_count
        \\    local.set $leaf_n
        \\    i32.const 0
        \\    local.set $elem_i
        \\    block $done
        \\      loop $scan_elem
        \\        local.get $elem_i
        \\        local.get $count
        \\        i32.ge_u
        \\        br_if $done
        \\        local.get $object
        \\        call $__arc_payload
        \\        i32.const 8
        \\        i32.add
        \\        local.get $elem_i
        \\        local.get $elem_bytes
        \\        i32.mul
        \\        i32.add
        \\        local.set $base
        \\        i32.const 0
        \\        local.set $leaf_i
        \\        block $leaf_done
        \\          loop $scan_leaf
        \\            local.get $leaf_i
        \\            local.get $leaf_n
        \\            i32.ge_u
        \\            br_if $leaf_done
        \\            local.get $base
        \\            local.get $type_id
        \\            local.get $leaf_i
        \\            call $__layout_managed_offset
        \\            i32.add
        \\            i32.load
        \\            local.tee $child
        \\            i32.eqz
        \\            if
        \\            else
        \\              local.get $child
        \\              call $__arc_dec_no_drain
        \\            end
        \\            local.get $leaf_i
        \\            i32.const 1
        \\            i32.add
        \\            local.set $leaf_i
        \\            br $scan_leaf
        \\          end
        \\        end
        \\        local.get $elem_i
        \\        i32.const 1
        \\        i32.add
        \\        local.set $elem_i
        \\        br $scan_elem
        \\      end
        \\    end
        \\  )
        \\  ;; arc-runtime managed child release v1
        \\  (func $__arc_release_managed_children (param $object i32)
        \\    (local $type_id i32)
        \\    (local $count i32)
        \\    (local $index i32)
        \\    (local $child i32)
        \\    local.get $object
        \\    call $__arc_type_id
        \\    local.set $type_id
        \\    local.get $type_id
        \\    i32.const 65535
        \\    i32.eq
        \\    if
        \\      local.get $object
        \\      call $__arc_release_storage_managed_children
        \\      return
        \\    end
        \\    local.get $type_id
        \\    call $__layout_is_storage_pack
        \\    if
        \\      local.get $object
        \\      local.get $type_id
        \\      call $__arc_release_storage_pack_children
        \\      return
        \\    end
        \\    local.get $type_id
        \\    call $__layout_managed_count
        \\    local.set $count
        \\    i32.const 0
        \\    local.set $index
        \\    block $done
        \\      loop $scan
        \\        local.get $index
        \\        local.get $count
        \\        i32.ge_u
        \\        br_if $done
        \\        local.get $object
        \\        call $__arc_payload
        \\        local.get $type_id
        \\        local.get $index
        \\        call $__layout_managed_offset
        \\        i32.add
        \\        i32.load
        \\        local.tee $child
        \\        i32.eqz
        \\        if
        \\        else
        \\          local.get $child
        \\          call $__arc_dec_no_drain
        \\        end
        \\        local.get $index
        \\        i32.const 1
        \\        i32.add
        \\        local.set $index
        \\        br $scan
        \\      end
        \\    end
        \\  )
        \\  (func $__arc_release (param $object i32)
        \\    local.get $object
        \\    call $__arc_release_managed_children
        \\    local.get $object
        \\    call $__small_block_for_object
        \\    i32.load8_u
        \\    i32.const 1
        \\    i32.eq
        \\    if
        \\      local.get $object
        \\      call $__arc_release_large
        \\    else
        \\      local.get $object
        \\      call $__arc_release_small
        \\    end
        \\  )
        \\  ;; arc-runtime refcount primitives v1
        \\  (func $__arc_inc (param $object i32) (result i32)
        \\    ;; arc-inc-zero-sentinel
        \\    local.get $object
        \\    i32.eqz
        \\    if (result i32)
        \\      i32.const 0
        \\    else
        \\      local.get $object
        \\      local.get $object
        \\      i32.load
        \\      i32.const 1
        \\      i32.add
        \\      i32.store
        \\      local.get $object
        \\    end
        \\  )
        \\  (func $__arc_dec_no_drain (param $object i32)
        \\    (local $next_rc i32)
        \\    ;; arc-dec-zero-sentinel
        \\    local.get $object
        \\    i32.eqz
        \\    if
        \\      return
        \\    end
        \\    local.get $object
        \\    local.get $object
        \\    i32.load
        \\    i32.const 1
        \\    i32.sub
        \\    local.tee $next_rc
        \\    i32.store
        \\    local.get $next_rc
        \\    i32.eqz
        \\    if
        \\      local.get $object
        \\      call $__release_worklist_push
        \\    end
        \\  )
        \\  (func $__arc_drain_release_worklist
        \\    (local $object i32)
        \\    block $done
        \\      loop $drain
        \\        call $__release_worklist_pop
        \\        local.tee $object
        \\        i32.eqz
        \\        br_if $done
        \\        local.get $object
        \\        call $__arc_release
        \\        br $drain
        \\      end
        \\    end
        \\  )
        \\  (func $__arc_dec (param $object i32)
        \\    local.get $object
        \\    call $__arc_dec_no_drain
        \\    call $__arc_drain_release_worklist
        \\  )
        \\  ;; arc-runtime object header accessors v0
        \\  (func $__arc_payload (param $object i32) (result i32)
        \\    local.get $object
        \\    i32.const 8
        \\    i32.add
        \\  )
        \\  (func $__arc_rc (param $object i32) (result i32)
        \\    local.get $object
        \\    i32.load
        \\  )
        \\  (func $__arc_type_id (param $object i32) (result i32)
        \\    local.get $object
        \\    i32.const 4
        \\    i32.add
        \\    i32.load
        \\  )
        \\  ;; arc-runtime storage range check v0
        \\  (func $__storage_check_range (param $storage i32) (param $offset i32) (param $width i32)
        \\    local.get $offset
        \\    local.get $width
        \\    i32.add
        \\    local.get $storage
        \\    call $__arc_payload
        \\    i32.load
        \\    i32.gt_u
        \\    if
        \\      unreachable
        \\    end
        \\  )
        \\  (func $__storage_equal_u8 (param $left i32) (param $right i32) (result i32)
        \\    (local $len i32)
        \\    (local $index i32)
        \\    local.get $left
        \\    local.get $right
        \\    i32.eq
        \\    if
        \\      i32.const 1
        \\      return
        \\    end
        \\    local.get $left
        \\    call $__arc_payload
        \\    i32.load
        \\    local.tee $len
        \\    local.get $right
        \\    call $__arc_payload
        \\    i32.load
        \\    i32.ne
        \\    if
        \\      i32.const 0
        \\      return
        \\    end
        \\    i32.const 0
        \\    local.set $index
        \\    block $done
        \\      loop $scan
        \\        local.get $index
        \\        local.get $len
        \\        i32.ge_u
        \\        br_if $done
        \\        local.get $left
        \\        call $__arc_payload
        \\        i32.const 8
        \\        i32.add
        \\        local.get $index
        \\        i32.add
        \\        i32.load8_u
        \\        local.get $right
        \\        call $__arc_payload
        \\        i32.const 8
        \\        i32.add
        \\        local.get $index
        \\        i32.add
        \\        i32.load8_u
        \\        i32.ne
        \\        if
        \\          i32.const 0
        \\          return
        \\        end
        \\        local.get $index
        \\        i32.const 1
        \\        i32.add
        \\        local.set $index
        \\        br $scan
        \\      end
        \\    end
        \\    i32.const 1
        \\  )
        \\  ;; arc-runtime storage write helpers v1
        \\  (func $__storage_set_u8 (param $storage i32) (param $index i32) (param $value i32) (result i32)
        \\    (local $len i32)
        \\    (local $next i32)
        \\    local.get $storage
        \\    local.get $index
        \\    i32.const 1
        \\    call $__storage_check_range
        \\    local.get $storage
        \\    call $__arc_payload
        \\    i32.load
        \\    local.set $len
        \\    local.get $storage
        \\    call $__arc_rc
        \\    i32.const 1
        \\    i32.eq
        \\    if
        \\      local.get $storage
        \\      call $__arc_payload
        \\      i32.const 8
        \\      i32.add
        \\      local.get $index
        \\      i32.add
        \\      local.get $value
        \\      i32.store8
        \\      local.get $storage
        \\      return
        \\    end
        \\    local.get $len
        \\    i32.const 8
        \\    i32.add
        \\    i32.const 1
        \\    call $__arc_alloc
        \\    local.set $next
        \\    local.get $next
        \\    call $__arc_payload
        \\    local.get $len
        \\    i32.store
        \\    local.get $next
        \\    call $__arc_payload
        \\    i32.const 4
        \\    i32.add
        \\    local.get $len
        \\    i32.store
        \\    local.get $next
        \\    call $__arc_payload
        \\    i32.const 8
        \\    i32.add
        \\    local.get $storage
        \\    call $__arc_payload
        \\    i32.const 8
        \\    i32.add
        \\    local.get $len
        \\    memory.copy
        \\    local.get $next
        \\    call $__arc_payload
        \\    i32.const 8
        \\    i32.add
        \\    local.get $index
        \\    i32.add
        \\    local.get $value
        \\    i32.store8
        \\    local.get $next
        \\  )
        \\  (func $__storage_put_u8 (param $storage i32) (param $value i32) (result i32)
        \\    (local $len i32)
        \\    (local $cap i32)
        \\    (local $next_len i32)
        \\    (local $next i32)
        \\    local.get $storage
        \\    call $__arc_payload
        \\    i32.load
        \\    local.set $len
        \\    local.get $storage
        \\    call $__arc_payload
        \\    i32.const 4
        \\    i32.add
        \\    i32.load
        \\    local.set $cap
        \\    local.get $len
        \\    i32.const 1
        \\    i32.add
        \\    local.set $next_len
        \\    local.get $storage
        \\    call $__arc_rc
        \\    i32.const 1
        \\    i32.eq
        \\    local.get $len
        \\    local.get $cap
        \\    i32.lt_u
        \\    i32.and
        \\    if
        \\      local.get $storage
        \\      call $__arc_payload
        \\      i32.const 8
        \\      i32.add
        \\      local.get $len
        \\      i32.add
        \\      local.get $value
        \\      i32.store8
        \\      local.get $storage
        \\      call $__arc_payload
        \\      local.get $next_len
        \\      i32.store
        \\      local.get $storage
        \\      return
        \\    end
        \\    local.get $next_len
        \\    i32.const 8
        \\    i32.add
        \\    i32.const 1
        \\    call $__arc_alloc
        \\    local.set $next
        \\    local.get $next
        \\    call $__arc_payload
        \\    local.get $next_len
        \\    i32.store
        \\    local.get $next
        \\    call $__arc_payload
        \\    i32.const 4
        \\    i32.add
        \\    local.get $next_len
        \\    i32.store
        \\    local.get $next
        \\    call $__arc_payload
        \\    i32.const 8
        \\    i32.add
        \\    local.get $storage
        \\    call $__arc_payload
        \\    i32.const 8
        \\    i32.add
        \\    local.get $len
        \\    memory.copy
        \\    local.get $next
        \\    call $__arc_payload
        \\    i32.const 8
        \\    i32.add
        \\    local.get $len
        \\    i32.add
        \\    local.get $value
        \\    i32.store8
        \\    local.get $next
        \\  )
        \\
    );
}


pub fn has_earlier_layout_type_id(layouts: []const StructLayout, type_id: usize) bool {
    for (layouts) |layout| {
        if (layout.type_id == type_id) return true;
    }
    return false;
}


pub fn aligned_arc_heap_base(string_data: []const StringData) usize {
    var end: usize = ARC_BLOCK_SIZE;
    for (string_data) |data| {
        end = @max(end, data.ptr + data.bytes.len);
    }
    return align_up(end + WASI_RESULT_AREA_BYTES + ARC_RELEASE_WORKLIST_BYTES, ARC_BLOCK_SIZE);
}


pub fn align_up(value: usize, alignment: usize) usize {
    return ((value + alignment - 1) / alignment) * alignment;
}


pub fn append_fmt(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    comptime fmt: []const u8,
    args: anytype,
) !void {
    const text = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(text);
    try out.appendSlice(allocator, text);
}


