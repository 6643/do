start() {
    a i32 = 1
    b u32 = 2
    c u64 = @as(u64, b)
    d i64 = @as(i64, a)
    e u32 = @as(u32, c)
    f f64 = @as(f64, b)
    g i32 = @as(i32, f)
    h f32 = @as(f32, f)
    i f64 = @as(f64, h)
    return
}
