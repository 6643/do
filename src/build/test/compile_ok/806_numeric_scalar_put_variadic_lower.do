append_i8(values [i8]) -> [i8] { return @put(values, 2, 3) }
append_i16(values [i16]) -> [i16] { return @put(values, 2, 3) }
append_i32(values [i32]) -> [i32] { return @put(values, 2, 3) }
append_i64(values [i64]) -> [i64] { return @put(values, 2, 3) }
append_u16(values [u16]) -> [u16] { return @put(values, 2, 3) }
append_u32(values [u32]) -> [u32] { return @put(values, 2, 3) }
append_u64(values [u64]) -> [u64] { return @put(values, 2, 3) }
append_isize(values [isize]) -> [isize] { return @put(values, 2, 3) }
append_usize(values [usize]) -> [usize] { return @put(values, 2, 3) }
append_f32(values [f32]) -> [f32] { return @put(values, 2.0, 3.0) }
append_f64(values [f64]) -> [f64] { return @put(values, 2.0, 3.0) }
append_bool(values [bool]) -> [bool] { return @put(values, false, true) }
start() {}
