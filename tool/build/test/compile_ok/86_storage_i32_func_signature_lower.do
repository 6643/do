make_nums() -> [i32] {
    xs [i32] = .{4, 5}
    return xs
}

first(xs [i32]) -> i32 {
    return @get(xs, 0)
}

start() {
    xs [i32] = make_nums()
    value i32 = first(xs)
    return
}
