#T
inner(value T) -> T {
    return value
}

#T
outer(value T) -> T {
    return inner(value)
}

test "compiled generic instance nested call lower" {
    seed [u8] = "a"
    out [u8] = outer(seed)
    if @eq(out, "a") return
}
