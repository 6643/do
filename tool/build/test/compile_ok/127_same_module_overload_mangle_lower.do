pick(x i32) -> i32 {
    return 11
}

pick(x i64) -> i64 {
    return 22
}

start() {
    value i64 = 1
    got i64 = pick(value)
    if @eq(got, 22) return
    return
}
