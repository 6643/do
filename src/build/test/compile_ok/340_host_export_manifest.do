sum(left i32, right i32) -> i32 {
    return @add(left, right)
}

pick(value i32) -> i32 {
    return value
}

pick(value i64) -> i64 {
    return value
}

echo(value text) -> text {
    return value
}

pair(value Tuple<i32, u8>) -> i32 {
    return 0
}

optional(value text | nil) -> i32 {
    return 0
}

Point {
    .x i32
    .y u8
}

point_x(point Point) -> i32 {
    return @get(point, .x)
}

.private_helper(value i32) -> i32 {
    return value
}
