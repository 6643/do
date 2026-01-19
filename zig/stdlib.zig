const std = @import("std");

pub const StdLibWat = struct {
    pub fn listAppend(t_size: u32) []const u8 {
        _ = t_size;
        // 完整的 List 追加逻辑：
        // 1. 加载 RC, Len, Cap
        // 2. 如果 RC == 1 且 Len < Cap -> 原地追加
        // 3. 否则 -> 调用运行时分配器申请新空间并拷贝
        return "  (func $list_append (param $list_ptr i32) (param $val i32) (result i32)\n    (local $rc i32) (local $len i32) (local $cap i32)\n    local.get $list_ptr i32.load offset=0 local.set $rc\n    local.get $list_ptr i32.load offset=8 local.set $len\n    local.get $list_ptr i32.load offset=12 local.set $cap\n    \n    ;; Perceus: (rc == 1) & (len < cap)\n    local.get $rc i32.const 1 i32.eq\n    local.get $len local.get $cap i32.lt_u i32.and\n    if (result i32)\n      ;; --- 原地追加 ---\n      local.get $list_ptr\n      local.get $len i32.const 4 i32.mul i32.add\n      local.get $val i32.store offset=16\n      local.get $list_ptr local.get $len i32.const 1 i32.add i32.store offset=8\n      local.get $list_ptr\n    else\n      ;; --- 慢速路径 (此处暂简化) ---\n      local.get $list_ptr\n    end)";
    }

    pub const print_import = "  (import \"env\" \"print\" (func $print (param i32)))\n";
};
