host_add = @env("dep_add", (i32, i32) -> i32)

pair(x i32) -> i32, bool {
    return x, true
}

make_bytes() -> [u8] {
    data [u8] = "from_lib"
    return data
}

make_byte_pair() -> [u8], [u8] {
    left [u8] = "left_lib"
    right [u8] = "right_lib"
    return left, right
}

use_host_add(x i32) -> i32 {
    return host_add(x, 1)
}
