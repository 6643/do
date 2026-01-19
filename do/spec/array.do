test "array with generic brackets" {
    // 1. 固定长度数组
    arr1 = set(Array<i32, 5>, [1, 2, 3, 4, 5])

    // 2. 长度推导 (由 set 自动处理)
    arr2 = set(Array<i32>, [10, 20, 30])

    // 3. 切片 (Slice<T>)
    s = slice(arr1, 1, 3) // 返回 Slice<i32>

    if i32(v) := get(s, .0) {
        print(v)
    }
}