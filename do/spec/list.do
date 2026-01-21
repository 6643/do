// List 通常作为动态增长的数组 (类似于 ArrayList/Vector)
// 或者链表，取决于具体实现，但语法层面统一使用 List<T>

test "static list instantiation" {
    // 使用新字面量语法实例化
    xs = List<i32>{1, 2, 3}
    
    // 方法调用 (假设支持 .push) 或者函数调用
    xs = push(xs, 4)
    
    // 遍历
    // for v in xs { ... }
}

test "empty list" {
    empty = List<Text>{}
}
