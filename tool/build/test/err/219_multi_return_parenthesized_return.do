pair() -> i32, i32 {
    return 1, 2
}

bad() -> i32, i32 {
    return (pair())
}
