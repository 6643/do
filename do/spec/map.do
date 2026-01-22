// 静态 Map 定义
// Map<K, V> 是内置类型，不再暴露底层 buckets/len/cap

test "static map" {
    // 编译器为 Map<Text, i32> 分配唯一 typeid
    m = Map<Text, i32>{
        "apple": 1,
        "banana": 2
    }
    
    // 单个更新
    m = put(m, "orange", 3)

    // 自更新
    m = put(m, "apple", v => add(v, 1))

    // 批量更新
    m = put(m, .{ 
        "banana": 8,
        "grape": 10,
        "melon": 11,
        "pear": 12,
        "apple": 13
    })

    if eq(get(m, "apple"), 13) {
        print("Static Map success")
    }

    // 批量获取
    {apple, banana} = get(m, {"apple", "banana"})
    print("apple: ${apple}, banana: ${banana}")
}