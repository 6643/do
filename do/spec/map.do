// 静态 Map 定义
// Map<K, V> 是内置类型，不再暴露底层 buckets/len/cap

test "static map" {
    // 编译器为 Map<Text, i32> 分配唯一 typeid
    m = Map<Text, i32>{
        "apple": 1,
        "banana": 2
    }
    
    // 空 Map
    m2 = Map<i32, f64>{}

    m = put(m, { "orange": 3 })
}