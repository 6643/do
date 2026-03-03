test "tuple and positioning" {
    // 实例化
    t = Tuple<i32, bool>{1, true}

    // 位置访问使用 index
    v0 = get(t, 0)
    v1 = get(t, 1)

    // 解构
    .{a, b} = get(t, .{0, 1})
    if eq(b, true) {
        print("Tuple access success")
    }

    // 更新
    t = set(t, 0, 2)
    t = set(t, 1, false)

    // 原地更新
    t = set(t, .{ 0: 2, 1: false })

    // 原地自更新
    t = set(t, .{ 0: v => add(v, 1), 1: v => not(v) })
}


new_tuple() Tuple<i32, bool> {
    t = Tuple<i32, bool>{1, true}
    t = set(t, 0, 2)
    t = set(t, 1, false)
    // 等效
    return t
}
