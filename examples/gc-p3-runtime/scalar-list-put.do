append_u32(input [u32], value u32) -> [u32] {
    return @put(input, value)
}

append_f64(input [f64], value f64) -> [f64] {
    return @put(input, value)
}

start() {}
