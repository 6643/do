test "tuple and positioning" {
    // 实例化
    t = Tuple<i32, bool>{1, true}

    // 位置访问使用 index
    v0 = t.0
    v1 = t.1

    // 显式获取 (无解构)
    a = t.0
    b = t.1

    // 原地更新
    // 假设 Tuple 是不可变的，或者用 set/copy 更新
    // t2 = set(t, { 1: false })
    
    if b == true {
        print("Tuple access success")
    }
}