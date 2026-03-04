to_i8(v i32) i8 => v
to_i8(v i64) i8 => v
as(v i32) i32 => v

test "convert by function" {
    x = to_i8(1)
    y = as(2)
    if x return
    if y return
}
