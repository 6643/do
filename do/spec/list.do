// List 通常作为动态增长的数组 (类似于 ArrayList/Vector)
// 或者链表，取决于具体实现，但语法层面统一使用 List<T>

test "static list instantiation" {
    // 使用新字面量语法实例化
    xs = List<i32>{1, 2, 3}
    
    // 方法调用 (假设支持 .push) 或者函数调用
    xs = push(xs, 4)

    // 批量更新
    xs = push(xs, .{ 5, 6, 7 })

    // 遍历
    loop v := next(xs) {
        print(v)
    }
    // 遍历带索引
    loop i, v := next(xs) {
        print(i, v)
    }


    // 显式设置
    xs = set(xs, 0, 10)
    print(xs)

    // 批量设置
    xs = set(xs, .{ 0: 10, 1: 20 })
    print(xs)



    // 长度
    len_xs = len(xs)
    print(len_xs)

    // 获取单个元素
    first = get(xs, 0)
    // 获取多个元素
    {first2, second} = get(xs, .{0, 1})
    print(first)
    print(first2)
    print(second)


    // 移除单个元素
    xs = remove(xs, 0)
    print(xs)

    // 移除多个元素
    xs = remove(xs, .{0, 1})
    print(xs)

}

test "empty list" {
    empty = List<Text>{}
}

test "list and struct integration" {
    // 实例化
    l = List<i32>{1, 2, 3}

    l = filter(l, n => eq(n % 2, 0))
    l = map(l, n => n * 10)
    s = join(l, ", ")

    print(s)
}



new_i32_list() List<i32> {
    // 自动推导类型
    => .{1, 2, 3}
}




 // 展开与合并：... (Spread/Splat)
combined_i32_list(a List<i32>, ...args i32) => List<i32>{...a, ...args}
test "spread and merge" {
    l1 = List<i32>{1, 2, 3}
    l2 = List<i32>{4, 5, 6}

    l3 = combined_i32_list(l1, ...l2, 7, 8, 9)
    print(l3)

    l4 = map(l3, n => n * 2)
    print(l4)

    s = join(l4, ", ")
    print(s)
}



 