start() {
    x i32 = @add(1, 2)
    n i32 = -3
    a u32 = @abs(n)
    c i32 = @min(n, 2, -5)
    d u32 = @max(a, 5, 8)
    big i64 = -9
    e u64 = @abs(big)
    f u64 = @max(e, 10, 11)
    tiny i8 = -128
    g u8 = @abs(tiny)
    return
}
