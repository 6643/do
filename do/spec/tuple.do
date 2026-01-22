test "tuple and positioning" {
    // 实例化
    t = Tuple<i32, bool>{1, true}

    // 位置访问使用 index
    v0 = get(t, 0)
    v1 = get(t, 1)

    // 显式获取 (解构)
    .{a, b} = get(t, .{0, 1})


    // 原地更新
    t2 = set(t, .{ 0: 2, 1: false })
    t3 = set(t, 0, 2)
    t4 = set(t, 1, false)

    if eq(b, true) {
        print("Tuple access success")
    }
}


new_tuple() Tuple<i32, bool> {
    // 自动推导类型
    => .{1, true}
}