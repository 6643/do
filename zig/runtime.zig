const std = @import("std");

/// 规范要求的 4KB 页面 Header 结构
pub const PageHeader = extern struct {
    next_page: u16,    // 0: 链表偏移，用于同规格空闲链表 (相对 heap_base 的页面索引或偏移)
    type_id: u8,       // 2: 规格标识 (Slab Class ID)
    page_rc: u8,       // 3: 页面级引用计数 (Perceus 优化用)
    free_cnt: u16,     // 4: 当前页剩余可用格数
    padding: u16,      // 6: 对齐补齐
    
    // 位图起始地址 (偏移 8)
    // 规范要求：u64[] 核心分配索引
    pub fn get_bitmap(self: *PageHeader) *u64 {
        const ptr = @as([*]u8, @ptrCast(self)) + 8;
        return @as(*u64, @ptrCast(@alignCast(ptr)));
    }
};

/// 槽位结构 (Slot Structure)
/// [ RC (4B) ] [ TypeID (2B) ] [ Payload... ] [ Padding ]
/// 注：为了简单起见，本实现暂固定 RC 为 u32, TypeID 为 u16
pub const SlotHeader = extern struct {
    rc: u32,
    type_id: u16,
};

pub const Runtime = struct {
    heap_base: usize,
    page_size: usize = 4096,
    header_total: usize = 64, // 预留 Header 空间（包含位图）

    pub fn init(base: usize) Runtime {
        return .{ .heap_base = base };
    }

    /// 分配指定 TypeID 的对象
    /// 这里的 slab_registry 通常存储在 WASM 的起始内存中
    pub fn alloc(self: *Runtime, type_id: u8, slot_size: usize, registry_ptr: usize) ?usize {
        _ = type_id; // 目前暂不支持完整 Slab 链表查找，默认在 registry 指向的页面分配
        return self.alloc_in_page(registry_ptr, slot_size);
    }

    pub fn alloc_in_page(self: *Runtime, page_ptr: usize, slot_size: usize) ?usize {
        const header = @as(*PageHeader, @ptrFromInt(page_ptr));
        if (header.free_cnt == 0) return null;

        const bitmap_ptr = header.get_bitmap();
        const val = bitmap_ptr.*;
        if (val == 0xFFFFFFFFFFFFFFFF) return null;

        const free_bit = @ctz(~val);
        
        bitmap_ptr.* |= (@as(u64, 1) << @as(u6, @intCast(free_bit)));
        header.free_cnt -= 1;

        const obj_ptr = page_ptr + self.header_total + (free_bit * slot_size);
        
        // 初始化 Slot Header
        const slot = @as(*SlotHeader, @ptrFromInt(obj_ptr));
        slot.rc = 1;
        slot.type_id = header.type_id;

        return obj_ptr;
    }

    pub fn free_in_page(self: *Runtime, page_ptr: usize, obj_ptr: usize, slot_size: usize) void {
        const header = @as(*PageHeader, @ptrFromInt(page_ptr));
        const index = (obj_ptr - (page_ptr + self.header_total)) / slot_size;
        const bitmap_ptr = header.get_bitmap();
        
        bitmap_ptr.* &= ~(@as(u64, 1) << @as(u6, @intCast(index)));
        header.free_cnt += 1;
    }

    /// 引用计数：增加
    pub fn inc_rc(_: *Runtime, obj_ptr: usize) void {
        if (obj_ptr == 0) return;
        const slot = @as(*SlotHeader, @ptrFromInt(obj_ptr));
        slot.rc += 1;
    }

    /// 引用计数：减少。若 RC 为 0，则需要调用释放逻辑 (由 Codegen 生成清理指令或在此递归)
    pub fn dec_rc(_: *Runtime, obj_ptr: usize) u32 {
        if (obj_ptr == 0) return 1; // nil 忽略
        const slot = @as(*SlotHeader, @ptrFromInt(obj_ptr));
        slot.rc -= 1;
        return slot.rc;
    }

    /// Perceus: 检查对象是否唯一 (RC == 1)
    pub fn is_unique(_: *Runtime, obj_ptr: usize) bool {
        if (obj_ptr == 0) return false;
        const slot = @as(*SlotHeader, @ptrFromInt(obj_ptr));
        return slot.rc == 1;
    }
};
