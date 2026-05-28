add(a i32, b i32) i32 => a

test "lambda callback site" {
    xs List<i32> = List<i32>{}
    result = map(xs, (x i32) => add(x, 1))
    return
}

test "inline lambda captures local" {
    xs List<i32> = List<i32>{}
    step i32 = 1
    result = map(xs, _(x i32) => add(x, step))
    return
}
