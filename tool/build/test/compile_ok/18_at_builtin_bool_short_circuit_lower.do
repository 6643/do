start() {
    a bool = @not(false)
    b bool = @and(true, a, @eq(1, 1))
    c bool = @or(false, b, @eq(1, 2))
    if b return
    return
}
