// 静态 Map 定义
Map<K, V> {
    .buckets ptr
    len      u32
    cap      u32
}

test "static map" {
    // 编译器为 Map<Text, i32> 分配唯一 typeid
    m = set(Map<Text, i32>, {
        .len: 0,
        .cap: 16
    })

    m = put(m, { "apple": 1 })
}