start() {
    a i32 = 1
    b u32 = 2
    c u64 = @to_u64(b)
    d i64 = @to_i64(a)
    e u32 = @to_u32(c)
    f f64 = @to_f64(b)
    g i32 = @to_i32(f)
    h f32 = @to_f32(f)
    i f64 = @to_f64(h)
    return
}
