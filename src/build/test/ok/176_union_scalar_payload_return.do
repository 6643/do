one() -> usize | nil {
    return 1
}

find_one(xs [i32]) -> usize | nil {
    loop value, index = xs {
        if @eq(value, 1) return index
    }
    return nil
}

test "union scalar payload return" {
    direct usize | nil = one()
    xs [i32] = .{}
    xs = @put(xs, 1)
    found usize | nil = find_one(xs)

    ok bool = true
    ok = @and(ok, @eq(direct, 1))
    ok = @and(ok, @eq(found, 0))
    if ok return
}
