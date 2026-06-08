S {
    a i32
    b i32
}

test "field segment before later named arg" {
    s S = S{a = 1, b = 2}
    t S = S{a = @get(s, .a), b = 3}
    if @eq(@get(t, .a), 1) return
}
