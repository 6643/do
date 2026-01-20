test "tuple and positioning" {
    // 实例化
    t = set(Tuple<i32, bool>, [1, true])

    // 位置访问使用 index (无前缀)
    v0 = get(t, 0)
    v1 = get(t, 1)

    // 解构 (内置语义)
    (a, b) = t

    // 原地更新
    t2 = set(t, { 1: false })
    
    if get(t2, 1) == false {
        print("Tuple update success")
    }
}