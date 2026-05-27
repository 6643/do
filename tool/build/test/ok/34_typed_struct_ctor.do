Config {
    a i32
    b i32
}

test "typed struct ctor" {
    config = Config{a = 1, b = 2}
    return
}
