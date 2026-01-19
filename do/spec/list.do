// 静态 List 定义
List<T> {
    .ptr ptr
    len  u32
    cap  u32
}

test "static list" {
    xs = set(List<i32>, [1, 2, 3])
    xs = push(xs, 4)
}